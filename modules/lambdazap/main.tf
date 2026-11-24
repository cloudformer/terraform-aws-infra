# lambdazap: OWASP ZAP scans of your own sites from a web UI; ≈ $0 when idle.
# https://github.com/cloudformer/lambdazap
#
#   Lambda + URL     the web UI and its API: starts / extends / stops scanners, adds tasks, follows logs, signs
#                    report links
#   CodeBuild        the scanners: one build each, on a fresh instance with the ZAP image, started from the UI with
#                    an instance size and a lease (how long it stays on; +1h from the UI, up to max_session_minutes,
#                    the build timeout); up to max_scanners at once; each takes the queued tasks one at a time and
#                    ends by itself when its lease runs out, or after idle_shutdown_minutes without a task
#   ECR repository   the ZAP image (official ZAP + the scanner loop), built and pushed with Docker on the machine
#                    running Terraform
#   S3 bucket        tasks/<task id>.json (the queue, written by the Lambda), claims/<task id>.json (a scanner takes
#                    a task by creating its claim with If-None-Match: *), leases/<scanner id>.json, and
#                    reports/<task id>/<host>/report.{html,json,md}; all expire after report_retention_days
#   SSM              secrets: one SecureString per name, /<project_name>/secrets/<name>, created with the value
#                    CHANGE-ME (never the real one: it would sit in the state); set it with aws ssm put-parameter

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p          = var.project_name
  account    = data.aws_caller_identity.me.account_id
  package    = "lambdazap==${var.lambdazap_version}" # a release from PyPI, never a working tree
  bucket     = "${local.p}-reports-${local.account}"
  tasks      = "tasks/"   # fixed layout: s3://<bucket>/tasks/<task id>.json
  claims     = "claims/"  #               s3://<bucket>/claims/<task id>.json
  leases     = "leases/"  #               s3://<bucket>/leases/<scanner id>.json
  reports    = "reports/" #               s3://<bucket>/reports/<task id>/<host>/...
  expire     = { reports = local.reports, tasks = local.tasks, claims = local.claims, leases = local.leases }
  secrets    = "/${local.p}/secrets/"
  secret_arn = "arn:aws:ssm:${data.aws_region.current.region}:${local.account}:parameter${local.secrets}"

  # every build runs the image's scanner loop; what to scan comes through tasks/
  buildspec = <<-EOT
    version: 0.2
    phases:
      build:
        commands:
          - lambdazap-scan
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
  value    = "CHANGE-ME" # a scan refuses to start while a secret still holds it

  lifecycle {
    ignore_changes = [value] # set with aws ssm put-parameter --overwrite; Terraform never reads it back
  }
}

# ---------------- packaging: lambdazap from PyPI (lambdazap/server = the Lambda, lambdazap/image = ZAP) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/lambdazap"]
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

# built on this machine with Docker, pushed only for the architecture the Lambda and scanners run on
module "image" {
  source         = "../../components/container_image"
  repository_url = module.ecr.url
  tag            = data.external.build.result.tag # the build context's content hash (build.py)
  context        = data.external.build.result.image
  architectures  = [var.architecture]
  build          = var.build_image
}

# ---------------- CodeBuild: the scanners, one build each ----------------
module "scanner" {
  source = "../../components/codebuild_project"

  name                   = "${local.p}-scanner"
  image                  = "${module.image.image}-${var.architecture}" # after the push
  ecr_repository_arn     = module.ecr.arn
  architecture           = var.architecture
  compute_type           = var.compute_type # the project's default; Start may pick another size per scanner
  timeout_minutes        = var.max_session_minutes
  concurrent_build_limit = var.max_scanners # the Lambda refuses one more Start; this is the backstop
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
        # one report per target, written as each finishes
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
    }] : []
  )
}

# ---------------- Lambda: the web UI + API ----------------
module "server" {
  source = "../../components/lambda"

  function_name        = "${local.p}-lambda"
  handler              = "lambdazap.server.lambda_function.lambda_handler"
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
    ALLOWED_TARGETS       = jsonencode(var.allowed_targets)
    BUCKET                = module.bucket.name
    PROJECT               = module.scanner.name
    LOG_GROUP             = module.scanner.log_group_name
    COMPUTE_TYPE          = var.compute_type
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
      # the reports: presigned download links (signed with this role)
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${module.bucket.arn}/${local.reports}*"
    },
    {
      # the queue (the only writer: every target checked against the allowlist first), the leases (Start, +1h),
      # the claims (read: who took a task; write: a cancel takes the claim first)
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
