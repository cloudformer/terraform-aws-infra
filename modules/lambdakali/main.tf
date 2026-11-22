# lambdakali: a Kali command-line console — start a scanner, type shell commands, they run on it. ≈ $0 when idle.
# A command console behind sign-in (http_auth / Cloudflare), for an advanced operator: no target allowlist (a free
# shell cannot enforce one); grant a command what it needs through scanner_policy_statements.
# https://github.com/cloudformer/lambdakali
#
#   Lambda + URL     the web console and its API: starts / extends / stops scanners, adds command tasks, follows
#                    logs, signs output links
#   CodeBuild        the scanners: one build each, on a fresh instance with a Kali image tier (slim / common /
#                    full), started from the UI with an instance size, an image and a lease; each runs the queued
#                    commands one at a time with bash -lc in /work
#   ECR repository   the Kali image tiers, arm64, built and pushed with Docker on the machine running Terraform
#   S3 bucket        tasks/<task id>.json (the queue), claims/<task id>.json, leases/<scanner id>.json, and
#                    reports/<task id>/output.txt; all expire after report_retention_days
#   SSM              secrets: one SecureString per name, /<project_name>/secrets/<name>, created with CHANGE-ME

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p          = var.project_name
  account    = data.aws_caller_identity.me.account_id
  package    = "lambdakali==${var.lambdakali_version}" # a release from PyPI, never a working tree
  bucket     = "${local.p}-reports-${local.account}"
  tasks      = "tasks/"
  claims     = "claims/"
  leases     = "leases/"
  reports    = "reports/"
  expire     = { reports = local.reports, tasks = local.tasks, claims = local.claims, leases = local.leases }
  secrets    = "/${local.p}/secrets/"
  secret_arn = "arn:aws:ssm:${data.aws_region.current.region}:${local.account}:parameter${local.secrets}"

  # one image per tier the deployment builds; the console picks which to Start (imageOverride)
  image_labels = {
    slim   = "slim · common tools"
    common = "common · ~80% of tools"
    full   = "full · everything (large)"
  }

  buildspec = <<-EOT
    version: 0.2
    phases:
      build:
        commands:
          - lambdakali-scan
  EOT
}

# ---------------- S3: the queue, the claims, the leases, the reports ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket     = module.bucket.name
  depends_on = [module.bucket]

  dynamic "rule" {
    for_each = local.expire
    content {
      id     = "expire-${rule.key}"
      status = "Enabled"
      filter {
        prefix = rule.value
      }
      expiration {
        days = var.report_retention_days
      }
    }
  }
}

# ---------------- SSM: the secrets, created empty (CHANGE-ME); the value is set outside Terraform ----------------
resource "aws_ssm_parameter" "secret" {
  for_each = toset(var.secrets)
  name     = "${local.secrets}${each.key}"
  type     = "SecureString"
  value    = "CHANGE-ME"

  lifecycle {
    ignore_changes = [value]
  }
}

# ---------------- packaging: lambdakali from PyPI (lambdakali/server = the Lambda, lambdakali/image = Kali) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/lambdakali"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.code
  output_path = "${path.module}/.build/code.zip"
}

module "ecr" {
  source = "../../components/ecr_repository"
  name   = local.p
}

# one image per tier (var.image_variants), built with Docker (arm64 only here), pushed to the one ECR repository
# with a tier-tagged name; only when the build context changes (tag = tier + content hash)
module "image" {
  for_each       = toset(var.image_variants)
  source         = "../../components/container_image"
  repository_url = module.ecr.url
  tag            = "${each.key}-${data.external.build.result.tag}" # <tier>-<content hash>
  context        = data.external.build.result.image
  build_args     = { KALI_TIER = each.key }
  architectures  = [var.architecture]
  build          = var.build_image
}

locals {
  # {tier: {uri, label}} passed to the Lambda; Start uses uri as imageOverride
  images = { for v in var.image_variants : v => {
    uri   = "${module.image[v].image}-${var.architecture}"
    label = lookup(local.image_labels, v, v)
  } }
}

# ---------------- CodeBuild: the scanners, one build each ----------------
module "scanner" {
  source = "../../components/codebuild_project"

  name                   = "${local.p}-scanner"
  image                  = local.images[var.default_image].uri # the project's default; Start overrides per scanner
  ecr_repository_arn     = module.ecr.arn
  architecture           = var.architecture
  compute_type           = var.compute_type
  timeout_minutes        = var.max_session_minutes
  concurrent_build_limit = var.max_scanners
  buildspec              = local.buildspec
  log_retention_days     = var.log_retention_days

  environment = {
    BUCKET                = module.bucket.name
    IDLE_SHUTDOWN_MINUTES = tostring(var.idle_shutdown_minutes)
    SECRETS               = join(",", var.secrets)
    SECRETS_PATH          = local.secrets
  }

  policy_statements = concat(
    [
      {
        # one output.txt per task, written as each finishes
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${module.bucket.arn}/${local.reports}*"
      },
      {
        # the queue and its own lease: read only
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.bucket.arn}/${local.tasks}*", "${module.bucket.arn}/${local.leases}*"]
      },
      {
        # a claim: created to take a task (If-None-Match: *), rewritten with the result
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${module.bucket.arn}/${local.claims}*"
      },
      {
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = module.bucket.arn
        Condition = { StringLike = { "s3:prefix" = ["${local.tasks}*", "${local.claims}*"] } }
      }
    ],
    length(var.secrets) > 0 ? [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = [for s in var.secrets : "${local.secret_arn}${s}"]
    }] : [],
    var.scanner_policy_statements # extra IAM the operator grants a command (e.g. s3:GetObject on a vault path)
  )
}

# ---------------- Lambda: the web console + API ----------------
module "server" {
  source = "../../components/lambda"

  function_name        = "${local.p}-lambda"
  handler              = "lambdakali.server.lambda_function.lambda_handler"
  runtime              = "python3.12"
  architecture         = var.architecture
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  timeout              = 30
  memory_size          = 256
  reserved_concurrency = -1
  url_auth             = var.function_url_auth

  environment = {
    HTTP_AUTH             = var.http_auth.enabled ? "1" : "0"
    USER_NAME             = var.http_auth.enabled ? var.http_auth.username : ""
    PASSWORD              = var.http_auth.enabled ? var.http_auth.password : ""
    CLOUDFLARE_AUTH       = var.cloudflare_auth.enabled ? "1" : "0"
    CLOUDFLARE_TEAM       = var.cloudflare_auth.enabled ? var.cloudflare_auth.team : ""
    CLOUDFLARE_AUD        = var.cloudflare_auth.enabled ? var.cloudflare_auth.aud : ""
    BUCKET                = module.bucket.name
    PROJECT               = module.scanner.name
    LOG_GROUP             = module.scanner.log_group_name
    COMPUTE_TYPE          = var.compute_type
    IMAGES                = jsonencode(local.images)
    DEFAULT_IMAGE         = var.default_image
    MAX_SCANNERS          = tostring(var.max_scanners)
    MAX_SESSION_MINUTES   = tostring(var.max_session_minutes)
    IDLE_SHUTDOWN_MINUTES = tostring(var.idle_shutdown_minutes)
  }

  policy_statements = [
    {
      # start / stop scanners and see them: this project only
      Effect   = "Allow"
      Action   = ["codebuild:StartBuild", "codebuild:StopBuild", "codebuild:BatchGetBuilds", "codebuild:ListBuildsForProject"]
      Resource = module.scanner.arn
    },
    {
      # a scanner's log read forward; a task's lines filtered out of its scanner's log
      Effect   = "Allow"
      Action   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
      Resource = ["${module.scanner.log_group_arn}", "${module.scanner.log_group_arn}:*"]
    },
    {
      # the output files: presigned download links (signed with this role)
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${module.bucket.arn}/${local.reports}*"
    },
    {
      # the queue (the only writer), the leases (Start, +1h), the claims (read + cancel)
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = ["${module.bucket.arn}/${local.tasks}*", "${module.bucket.arn}/${local.leases}*", "${module.bucket.arn}/${local.claims}*"]
    },
    {
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = module.bucket.arn
      Condition = { StringLike = { "s3:prefix" = ["${local.reports}*", "${local.tasks}*", "${local.claims}*"] } }
    }
  ]
}
