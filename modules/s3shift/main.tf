# s3shift: Redshift SQL on DuckDB in a Lambda, over your own S3 and RDS data; a query-editor console at the
# Function URL, the same URL serves s3shift.redshift_connector. https://github.com/cloudformer/s3shift

data "aws_caller_identity" "me" {}

locals {
  package = "s3shift==${var.s3shift_version}" # a release from PyPI, never a working tree
  bucket  = var.bucket != null ? var.bucket : "${var.project_name}-data-${data.aws_caller_identity.me.account_id}"
}

# ---------------- S3: the catalog, managed tables (Parquet) and large results ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

# a large result is written to results/ and served page by page; nobody needs it after a day
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket     = module.bucket.name
  depends_on = [module.bucket]

  rule {
    id     = "expire-large-results"
    status = "Enabled"
    filter {
      prefix = "results/"
    }
    expiration {
      days = 1
    }
  }
}

# ---------------- packaging: s3shift from PyPI (s3shift.server) + its layer (DuckDB, RDS clients) ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/s3shift"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.code
  excludes    = ["**/__pycache__/**", "requirements.txt", "__init__.py"] # the layer's pins; the pip package's marker
  output_path = "${path.module}/.build/server.zip"
}

module "layer" {
  source     = "../../components/lambda_layer"
  name       = "${var.project_name}-deps"
  source_dir = data.external.build.result.layer
}

# ---------------- Lambda: one function, console + query API ----------------
module "server" {
  source = "../../components/lambda"

  function_name        = "${var.project_name}-lambda"
  handler              = "lambda_function.lambda_handler" # the zip's root is s3shift/server
  runtime              = "python3.12"
  architecture         = "x86_64" # the layer's wheels (build.py)
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  layers               = [module.layer.arn]
  timeout              = 900           # Lambda's maximum: a query has 15 minutes
  memory_size          = var.memory_mb # more memory = more CPU = faster scans
  ephemeral_storage_mb = 10240         # /tmp: the S3 file cache and DuckDB's spill space
  reserved_concurrency = -1
  url_auth             = var.function_url_auth

  vpc_subnet_ids         = var.vpc_subnet_ids
  vpc_security_group_ids = var.vpc_security_group_ids

  environment = {
    BUCKET    = module.bucket.name
    USER_NAME = var.console_auth_username
    PASSWORD  = var.console_auth_password
    CONSOLE   = var.console ? "1" : "0"
  }

  # its own bucket read / write; your data buckets (read_buckets) read-only
  policy_statements = concat([
    {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${module.bucket.arn}/*"
    },
    {
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = module.bucket.arn
    }
    ], length(var.read_buckets) == 0 ? [] : [
    {
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = [for b in var.read_buckets : "arn:aws:s3:::${b}/*"]
    },
    {
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [for b in var.read_buckets : "arn:aws:s3:::${b}"]
    }
  ])
}
