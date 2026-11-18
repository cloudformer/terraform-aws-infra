# Snapshots of one bucket into <source bucket>-backup, taken only when something changed; no S3 versioning needed:
#   bucket    <source bucket>-backup, snapshots at <UTC time>/<key> + manifest.json, expired after keep_days
#   Lambda    <name>-lambda (backup.py, in this component): checks the objects under prefixes; copies all of them
#             when there is no snapshot yet, they changed, or the newest is half of keep_days old
#   schedule  EventBridge Scheduler group <name>, one check every <every> (1h, 6h, 1d, 7d, ...)
# Rules and restore: README.md

locals {
  bucket = "${var.source_bucket}-backup"
  n      = tonumber(substr(var.every, 0, length(var.every) - 1))
  unit   = endswith(var.every, "h") ? "hour" : "day"
  rate   = "rate(${local.n} ${local.unit}${local.n == 1 ? "" : "s"})"
  hours  = local.n * (local.unit == "hour" ? 1 : 24)

  # a fresh snapshot is forced after half of keep_days (whole days, at least 1), so one exists before the
  # newest expires; that needs a check at least that often
  force_after_days = max(1, floor(var.keep_days / 2))
}

# ---------------- the backup bucket: snapshots expire after keep_days ----------------
module "bucket" {
  source        = "../s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket     = module.bucket.name
  depends_on = [module.bucket]

  rule {
    id     = "expire-snapshots"
    status = "Enabled"
    filter {}
    expiration {
      days = var.keep_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  lifecycle {
    precondition {
      condition     = local.hours <= local.force_after_days * 24
      error_message = "s3_backup: every ${var.every} is longer than ${local.force_after_days}d (half of keep_days ${var.keep_days}); a snapshot could expire before the next one. Check more often or keep longer."
    }
    precondition {
      condition     = length(local.bucket) <= 63
      error_message = "s3_backup: the backup bucket ${local.bucket} is longer than 63 characters; use a shorter project_name or bucket."
    }
  }
}

# ---------------- the copier: backup.py, shipped with this component ----------------
data "archive_file" "code" {
  type        = "zip"
  source_file = "${path.module}/backup.py"
  output_path = "${path.module}/.build/backup.zip"
}

module "function" {
  source = "../lambda"

  function_name        = "${var.name}-lambda"
  function_url         = false
  handler              = "backup.handler"
  runtime              = "python3.12"
  architecture         = "arm64"
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  timeout              = 900
  memory_size          = 256
  reserved_concurrency = -1

  environment = {
    SOURCE_BUCKET     = var.source_bucket
    BACKUP_BUCKET     = module.bucket.name
    PREFIXES          = jsonencode(var.prefixes)
    FORCE_AFTER_HOURS = local.force_after_days * 24
  }

  # read the source (only under prefixes), find the newest snapshot (list + manifest.json), write the backup bucket;
  # never delete anything. *Tagging: a copy carries the object's tags (e.g. a provider's default_tags), which needs both sides
  policy_statements = [
    {
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = var.source_bucket_arn
      Condition = { StringLike = { "s3:prefix" = [for p in var.prefixes : "${p}*"] } }
    },
    {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectTagging"]
      Resource = [for p in var.prefixes : "${var.source_bucket_arn}/${p}*"]
    },
    {
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = module.bucket.arn
    },
    {
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${module.bucket.arn}/*/manifest.json"
    },
    {
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:PutObjectTagging"]
      Resource = "${module.bucket.arn}/*"
    }
  ]
}

# ---------------- the schedule ----------------
module "scheduler" {
  source = "../scheduler_group"
  name   = var.name
  policy_statements = [
    { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = module.function.function_arn }
  ]
}

resource "aws_scheduler_schedule" "this" {
  name                = var.name
  group_name          = module.scheduler.name
  schedule_expression = local.rate

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.function.function_arn
    role_arn = module.scheduler.role_arn
  }
}
