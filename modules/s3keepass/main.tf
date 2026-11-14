# s3keepass: KeePass vaults (.kdbx) on S3, opened in a web UI served by a Lambda Function URL; decrypted only in
# the browser. https://github.com/cloudformer/s3keepass

data "aws_caller_identity" "me" {}

locals {
  package = "s3keepass==${var.s3keepass_version}" # a release from PyPI, never a working tree
  prefix  = "keepass/"                            # fixed layout: s3://<bucket>/keepass/[<folder>/]<vault>.kdbx
  log     = "log/"                                # access records: s3://<bucket>/log/<vault key>/<time>-<random>.json
  custom  = "config/custom_template.json"         # the deployment's overrides of the package's base_template.json
  bucket  = var.bucket != null ? var.bucket : "${var.project_name}-vaults-${data.aws_caller_identity.me.account_id}"

  # custom_template without the fields left unset (null): only what is set overrides the base template; {} = none.
  # try(): custom_template or its kdf may be null.
  custom_fields   = try({ for k, v in var.custom_template : k => v if v != null && k != "kdf" }, {})
  custom_kdf      = try({ for k, v in var.custom_template.kdf : k => v if v != null }, {})
  custom_template = merge(local.custom_fields, { for k in(length(local.custom_kdf) > 0 ? ["kdf"] : []) : k => local.custom_kdf })
}

# ---------------- S3: every vault is one .kdbx under keepass/ in this private, versioned bucket ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
  versioning    = true # every save is a new object version: an older vault is one click away in the UI (Versions)
}

# old versions: keep the newest keep_versions per vault (older ones go a day after they are replaced);
# access records expire after log_retention_days
resource "aws_s3_bucket_lifecycle_configuration" "vaults" {
  bucket     = module.bucket.name
  depends_on = [module.bucket]

  rule {
    id     = "keep-newest-versions"
    status = "Enabled"
    filter {
      prefix = local.prefix
    }
    noncurrent_version_expiration {
      noncurrent_days           = 1
      newer_noncurrent_versions = var.keep_versions
    }
    expiration {
      expired_object_delete_marker = true
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "expire-access-records"
    status = "Enabled"
    filter {
      prefix = local.log
    }
    expiration {
      days = var.log_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# the custom template (advanced settings), always written ({} when unset = the package's base_template.json as is):
# a missing object would need s3:ListBucket on the whole bucket to read as 404 instead of 403
resource "aws_s3_object" "custom_template" {
  bucket       = module.bucket.name
  key          = local.custom
  content      = jsonencode(local.custom_template)
  content_type = "application/json"
}

# ---------------- packaging: s3keepass from PyPI (s3keepass.server: the vault API + the web UI) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/server"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.dir
  output_path = "${path.module}/.build/server.zip"
}

# ---------------- Lambda: one function, web UI + vault API ----------------
module "server" {
  source = "../../components/lambda"

  function_name        = "${var.project_name}-lambda"
  handler              = "s3keepass.server.lambda_function.lambda_handler"
  runtime              = "python3.12"
  architecture         = var.architecture
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  timeout              = 30
  memory_size          = 256
  reserved_concurrency = -1
  url_auth             = var.function_url_auth

  environment = {
    USER_NAME = var.console_auth_username
    PASSWORD  = var.console_auth_password
    CONSOLE   = var.console ? "1" : "0"
    BUCKET    = module.bucket.name
  }

  policy_statements = [
    {
      # the vaults: read (and older versions), save, delete
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${module.bucket.arn}/${local.prefix}*.kdbx"
    },
    {
      # access records: write one per event, read them back for the UI; never delete
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${module.bucket.arn}/${local.log}*"
    },
    {
      # the custom template: read only
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${module.bucket.arn}/${local.custom}"
    },
    {
      Effect    = "Allow"
      Action    = ["s3:ListBucket", "s3:ListBucketVersions"]
      Resource  = module.bucket.arn
      Condition = { StringLike = { "s3:prefix" = ["${local.prefix}*", "${local.log}*"] } }
    }
  ]
}
