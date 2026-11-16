# lambdavault: HashiCorp Vault, the official binary unchanged, in a Lambda container image; data in S3, the unseal
# key in SSM Parameter Store (seal = ssm, free) or a KMS key (seal = kms). ≈ $0 when idle.
# https://github.com/cloudformer/lambdavault
#
#   S3 bucket        Vault's storage (s3 backend; Vault encrypts everything before it is written)
#   s3_backup        optional scheduled snapshots into <bucket>-backup
#   ECR repository   the Vault image, arm64 + x86_64, built and pushed with Docker on the machine running Terraform
#   Lambda vault     Vault + Lambda Web Adapter; reserved concurrency 1 (the s3 backend has no lock), no URL
#   Lambda proxy     the Function URL (VAULT_ADDR): queues callers for the one Vault; seal = ssm: stores the key at init
#   seal = kms       a KMS key, alias/<project_name>-seal: Vault unseals itself (awskms)
#   seal = ssm       no resource: `vault operator init` (through the proxy) writes the SecureString
#                    /<project_name>/unseal-key; the Vault function reads it at every cold start

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p                    = var.project_name
  account              = data.aws_caller_identity.me.account_id
  package              = "lambdavault==${var.lambdavault_version}" # a release from PyPI, never a working tree
  bucket               = var.bucket != null ? var.bucket : "${local.p}-data-${local.account}"
  ssm                  = var.seal.type == "ssm"
  unseal_key_parameter = "/${local.p}/unseal-key"
  unseal_key_arn       = "arn:aws:ssm:${data.aws_region.current.region}:${local.account}:parameter${local.unseal_key_parameter}"
}

# ---------------- storage: Vault's s3 backend ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

# ---------------- backup (s3_backup): snapshots of the whole bucket into <bucket>-backup ----------------
# Vault writes many small objects; a snapshot taken during a write may catch it half done
module "backup" {
  count             = var.s3_backup.enabled ? 1 : 0
  source            = "../../components/s3_backup"
  name              = "${local.p}-backup"
  source_bucket     = module.bucket.name
  source_bucket_arn = module.bucket.arn
  prefixes          = [""]
  every             = var.s3_backup.every
  keep_days         = var.s3_backup.keep_days
  force_destroy     = var.force_destroy
}

# ---------------- the seal (seal = kms only; seal = ssm keeps the key in SSM, written at init) ----------------
module "seal" {
  count                   = var.seal.type == "kms" ? 1 : 0
  source                  = "../../components/kms_key"
  alias                   = "${local.p}-seal"
  description             = "${local.p}: Vault auto-unseal"
  deletion_window_in_days = var.seal.kms_deletion_window_days
}

# ---------------- packaging: lambdavault from PyPI (lambdavault/server = the image, lambdavault/proxy) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/lambdavault"]
}

data "archive_file" "proxy" {
  type        = "zip"
  source_file = "${data.external.build.result.proxy}/lambda_function.py"
  output_path = "${path.module}/.build/proxy.zip"
}

module "ecr" {
  source = "../../components/ecr_repository"
  name   = local.p
}

# built on this machine with Docker, pushed for both architectures; only when the build context changes
module "image" {
  source         = "../../components/container_image"
  repository_url = module.ecr.url
  tag            = data.external.build.result.tag # the build context's content hash (build.py)
  context        = data.external.build.result.server
  build          = var.build_image
}

# ---------------- Vault: one Lambda, no URL of its own (only the proxy invokes it) ----------------
module "vault" {
  source = "../../components/lambda"

  function_name        = "${local.p}-lambda"
  role_name            = "${local.p}-lambda-role"
  policy_name          = "${local.p}-lambda-role-policy"
  function_url         = false
  package_type         = "Image"
  image_uri            = "${module.image.image}-${var.architecture}" # after the push
  architecture         = var.architecture
  timeout              = 30
  memory_size          = var.memory_size
  reserved_concurrency = 1 # one Vault process at a time: the s3 backend has no lock, two writers would corrupt it

  environment = merge(
    { AWS_S3_BUCKET = module.bucket.name, LAMBDAVAULT_SEAL = var.seal.type },
    local.ssm ? { LAMBDAVAULT_UNSEAL_KEY_PARAMETER = local.unseal_key_parameter } : { VAULT_AWSKMS_SEAL_KEY_ID = one(module.seal[*].key_id) },
  )

  policy_statements = concat([
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = module.bucket.arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${module.bucket.arn}/*" },
    ], local.ssm ? [
    # a SecureString under AWS's own aws/ssm key: its key policy lets SSM decrypt for callers in this account
    { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = local.unseal_key_arn },
    ] : [
    { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"], Resource = one(module.seal[*].arn) },
  ])
}

# ---------------- the proxy: the public entrance, queues callers for the one Vault ----------------
# url_auth NONE: the URL is public and Vault's own tokens are the gate (as on an EC2 Vault behind a load balancer).
module "proxy" {
  source = "../../components/lambda"

  function_name        = "${local.p}-proxy-lambda"
  role_name            = "${local.p}-proxy-role"
  policy_name          = "${local.p}-proxy-role-policy"
  handler              = "lambda_function.lambda_handler"
  runtime              = "python3.12"
  architecture         = var.architecture
  filename             = data.archive_file.proxy.output_path
  source_code_hash     = data.archive_file.proxy.output_base64sha256
  timeout              = 60 # up to 25 s waiting for a turn + up to 30 s for Vault
  memory_size          = 128
  reserved_concurrency = -1
  url_auth             = "NONE"

  environment = merge(
    { VAULT_FUNCTION = module.vault.function_name, SEAL = var.seal.type },
    local.ssm ? { UNSEAL_KEY_PARAMETER = local.unseal_key_parameter } : {},
  )

  policy_statements = concat([
    { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = module.vault.function_arn },
    ], local.ssm ? [
    { Effect = "Allow", Action = ["ssm:PutParameter"], Resource = local.unseal_key_arn }, # at `vault operator init` only
  ] : [])
}
