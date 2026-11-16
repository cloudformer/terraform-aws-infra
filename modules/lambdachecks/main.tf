# lambdachecks: Healthchecks (cron / scheduled-job monitoring), unchanged, on Lambda behind a Function URL, with its
# database on s3rds (its released server as a Lambda + a private S3 bucket) in the same stack. ≈ $0 when idle.
# https://github.com/cloudformer/lambdachecks
#
#   Lambda <p>-lambda      Function URL: Healthchecks (UI, API, ping URLs); the setup page until the first account
#   Lambda <p>-manage      manage.py, no URL, 15 minutes (the setup page starts migrate here)
#   Lambda <p>-db-lambda   s3rds' server: Function URL, Healthchecks' database (and s3rds' console)
#   S3 bucket              the database file, db/<db_name>.sqlite

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p       = var.project_name
  account = data.aws_caller_identity.me.account_id
  package = "lambdachecks==${var.lambdachecks_version}" # a release from PyPI, never a working tree
  bucket  = var.bucket != null ? var.bucket : "${local.p}-db-${local.account}"
  prefix  = "db/" # s3rds' fixed layout: s3://<bucket>/db/<db>.sqlite

  # by name, not module.manage.function_arn: the manage function's environment holds the web function's URL, and
  # the web function's policy names the manage function; a reference both ways would be a cycle
  manage_name = "${local.p}-manage"
  manage_arn  = "arn:aws:lambda:${data.aws_region.current.region}:${local.account}:function:${local.manage_name}"

  # Healthchecks' settings (local_settings.py reads them); the web and the manage function share them
  env = {
    SECRET_KEY        = var.secret_key
    DB_HOST           = trimsuffix(trimprefix(module.db.url, "https://"), "/")
    DB_NAME           = var.db_name
    DB_USER           = var.console_auth_username
    DB_PASSWORD       = var.console_auth_password
    REGISTRATION_OPEN = var.registration_open ? "True" : "False"
  }
}

# ---------------- packaging: lambdachecks from PyPI + Healthchecks' release + s3rds' server, both architectures ----------------
# build.py stages .build/lambdachecks/{server,db}-<arch> at plan time (Docker; nothing runs again for the same release)
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/lambdachecks"]
}

data "archive_file" "server" {
  type        = "zip"
  source_dir  = data.external.build.result["server-${var.architecture}"]
  output_path = "${path.module}/.build/server-${var.architecture}.zip"
}

data "archive_file" "db" {
  type        = "zip"
  source_dir  = data.external.build.result["db-${var.architecture}"]
  output_path = "${path.module}/.build/db-${var.architecture}.zip"
}

# ================ the database: s3rds (its released server), private to this deployment ================
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

module "db" {
  source = "../../components/lambda"

  function_name        = "${local.p}-db-lambda"
  policy_name          = "${local.p}-db-lambda-role-policy"
  handler              = "lambda_function.lambda_handler"
  runtime              = "python3.12" # s3rds' own runtime (build.py)
  architecture         = var.architecture
  filename             = data.archive_file.db.output_path
  source_code_hash     = data.archive_file.db.output_base64sha256
  timeout              = 15
  memory_size          = 256
  reserved_concurrency = 1      # s3rds: one writer globally (the ETag CAS in its code is the second guard)
  url_auth             = "NONE" # Healthchecks connects with s3rds' user / password (HTTP Basic), it cannot sign

  environment = {
    DB_BUCKET   = module.bucket.name
    DB_PREFIX   = local.prefix
    DB_USER     = var.console_auth_username
    DB_PASSWORD = var.console_auth_password
    CONSOLE     = var.console ? "1" : "0" # s3rds' console at db_url: Healthchecks' tables and rows
  }

  policy_statements = [
    {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${module.bucket.arn}/${local.prefix}*.sqlite"
    },
    {
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = module.bucket.arn
      Condition = { StringLike = { "s3:prefix" = ["${local.prefix}*"] } }
    },
  ]
}

# ================ Healthchecks ================

# the web: Healthchecks (UI, API, ping URLs) behind a public Function URL; Healthchecks' own login is the gate for
# the UI, ping URLs are public by design. It reaches the database over HTTPS with s3rds' credentials.
module "server" {
  source = "../../components/lambda"

  function_name        = "${local.p}-lambda"
  policy_name          = "${local.p}-lambda-role-policy"
  handler              = "lambda_function.lambda_handler"
  runtime              = "python3.13"
  architecture         = var.architecture
  filename             = data.archive_file.server.output_path
  source_code_hash     = data.archive_file.server.output_base64sha256
  timeout              = 30
  memory_size          = var.memory_size
  reserved_concurrency = -1
  url_auth             = "NONE"

  # SITE_ROOT comes from the first request (lambda_function.py); the setup page starts migrate in the manage function
  environment = merge(local.env, { MANAGE_FUNCTION = local.manage_name })

  policy_statements = [
    { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = local.manage_arn },
  ]
}

# manage.py: the same package, no URL, 15 minutes. The setup page starts migrate here; by hand:
# aws lambda invoke --function-name <project_name>-manage --payload '{"manage": ["migrate", "--noinput"]}' ...
module "manage" {
  source = "../../components/lambda"

  function_name        = local.manage_name
  function_url         = false
  handler              = "lambda_function.manage_handler"
  runtime              = "python3.13"
  architecture         = var.architecture
  filename             = data.archive_file.server.output_path
  source_code_hash     = data.archive_file.server.output_base64sha256
  timeout              = 900
  memory_size          = var.memory_size
  reserved_concurrency = 1 # one migrate at a time; a second click waits for the first

  environment = merge(local.env, { SITE_ROOT = trimsuffix(module.server.url, "/") })

  policy_statements = [] # its log group only: it talks to the database over HTTPS
}

# a failed migrate is not retried behind your back: the setup page shows the progress, you click again
resource "aws_lambda_function_event_invoke_config" "manage" {
  function_name          = module.manage.function_name
  maximum_retry_attempts = 0
}
