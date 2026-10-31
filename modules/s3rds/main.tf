# s3rds: a serverless MySQL / PostgreSQL / SQLite-compatible database. Each database is one SQLite file on S3;
# a Lambda Function URL is the endpoint. https://github.com/cloudformer/s3rds

data "aws_caller_identity" "me" {}

locals {
  package = "s3rds[server]==${var.s3rds_version}" # a release from PyPI, never a working tree
  prefix  = "db/"                                 # fixed layout: s3://<bucket>/db/<db>.sqlite

  # the endpoints run the same code, each with its own role:
  #   rw  the database, one writer globally (reserved concurrency 1; the ETag CAS in the code is the second guard)
  #   ro  read-only (READONLY=1): not a replica, it reads the same S3 file, zero copy, zero lag; scales with demand.
  #       Only when db_ro = true; its role can read the databases and nothing else, so even a bug in the code
  #       cannot write to S3 from it.
  all_endpoints = {
    rw = { function_name = "${var.project_name}-db-lambda", readonly = "0", concurrency = 1, s3 = ["s3:GetObject", "s3:PutObject"] }
    ro = { function_name = "${var.project_name}-db-ro-lambda", readonly = "1", concurrency = -1, s3 = ["s3:GetObject"] }
  }
  endpoints = { for k, e in local.all_endpoints : k => e if k == "rw" || var.db_ro }
}

# ---------------- S3: every database file lives in this one private bucket ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = "${var.project_name}-db-${data.aws_caller_identity.me.account_id}" # unique per account
  force_destroy = var.force_destroy
}

# ---------------- packaging: s3rds[server] from PyPI (s3rds.server + the pinned engine, Linux wheels) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/server"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.dir
  output_path = "${path.module}/.build/server.zip"
}

# ---------------- Lambda: the database (web console + API), read/write and read-only ----------------
module "endpoint" {
  source   = "../../components/lambda"
  for_each = local.endpoints

  function_name        = each.value.function_name
  handler              = "s3rds.server.lambda_function.lambda_handler"
  runtime              = "python3.12"
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  timeout              = 15
  memory_size          = 256
  reserved_concurrency = each.value.concurrency
  url_auth             = var.function_url_auth

  environment = {
    DB_BUCKET   = module.bucket.name
    DB_PREFIX   = local.prefix
    DB_USER     = var.console_auth_username
    DB_PASSWORD = var.console_auth_password
    READONLY    = each.value.readonly
    CONSOLE     = var.console ? "1" : "0"
  }

  # rw: GetObject + PutObject; ro: GetObject only. Both may list db/ (the console's database list).
  policy_statements = [
    {
      Effect   = "Allow"
      Action   = each.value.s3
      Resource = "${module.bucket.arn}/${local.prefix}*.sqlite"
    },
    {
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = module.bucket.arn
      Condition = { StringLike = { "s3:prefix" = ["${local.prefix}*"] } }
    }
  ]
}
