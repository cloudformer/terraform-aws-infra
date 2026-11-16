# Mock tests for modules/s3keepass: plan only, every provider mocked — no AWS account, no pip build.
# Run from the repo root: make test

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

mock_provider "external" {
  override_during = plan

  mock_data "external" {
    defaults = { result = { dir = "/mock/build" } }
  }
}

mock_provider "archive" {
  override_during = plan

  mock_data "archive_file" {
    defaults = { output_path = "/mock/server.zip", output_base64sha256 = "bW9jaw==" }
  }
}

variables {
  project_name = "test"
  http_auth    = { enabled = true, username = "admin", password = "a-password-of-16+chars" }
}

# Defaults: bucket <project>-vaults-<account>, versioned; one arm64 function; the custom template is {} (base as is).
run "defaults" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  assert {
    condition     = module.bucket.name == "test-vaults-123456789012"
    error_message = "bucket name should be <project_name>-vaults-<account id>"
  }

  assert {
    condition     = length(module.bucket.versioning_ids) == 1
    error_message = "the vault bucket should be versioned"
  }

  assert {
    condition     = module.server.function_name == "test-lambda"
    error_message = "function name should be <project_name>-lambda"
  }

  assert {
    condition     = aws_s3_object.custom_template.content == "{}"
    error_message = "without custom_template the uploaded overrides should be {}"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.vaults.rule[0].noncurrent_version_expiration[0].newer_noncurrent_versions == 5
    error_message = "keep_versions should default to 5"
  }
}

# bucket set: that name, nothing derived (an existing deployment keeps its vaults).
run "bucket_override" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    bucket = "my-vaults"
  }

  assert {
    condition     = module.bucket.name == "my-vaults"
    error_message = "bucket should be used as given"
  }
}

# custom_template: only the fields set reach S3; kdf keeps only its set fields (the Lambda merges them over the base).
run "custom_template_fields" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    custom_template = { kdf = { unlock_ms = 3000 }, recycle_bin = true }
  }

  assert {
    condition     = aws_s3_object.custom_template.content == jsonencode({ kdf = { unlock_ms = 3000 }, recycle_bin = true })
    error_message = "the custom template should hold exactly the fields set"
  }
}

# A password under 16 characters is refused at plan time.
run "short_password_rejected" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    http_auth = { enabled = true, username = "admin", password = "short" }
  }

  expect_failures = [var.http_auth]
}

# Cloudflare alone is a valid sign-in: no user or password needed.
run "cloudflare_alone" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    http_auth       = { enabled = false }
    cloudflare_auth = { enabled = true, team = "myteam", aud = "aud-tag" }
  }

  assert {
    condition     = module.server.function_name == "test-lambda"
    error_message = "cloudflare_auth alone should plan"
  }
}

# Cloudflare on without its aud is refused at plan time.
run "cloudflare_without_aud_rejected" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    cloudflare_auth = { enabled = true, team = "myteam" }
  }

  expect_failures = [var.cloudflare_auth]
}

# No sign-in method on is refused at plan time: a vault page is never deployed open.
run "no_sign_in_rejected" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    http_auth       = { enabled = false, username = "admin", password = "a-password-of-16+chars" }
    cloudflare_auth = { enabled = false }
  }

  expect_failures = [var.cloudflare_auth]
}

# An out-of-range KDF memory is refused at plan time.
run "kdf_memory_rejected" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    custom_template = { kdf = { memory_mib = 4096 } }
  }

  expect_failures = [var.custom_template]
}

# s3_backup off (the default): no backup bucket, no copier, no schedule.
run "backup_off" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  assert {
    condition     = length(module.backup) == 0 && output.backup_bucket == null
    error_message = "s3_backup should be off by default"
  }
}

# s3_backup on: <bucket>-backup, the copier, a schedule at the chosen frequency.
run "backup_on" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    s3_backup = { enabled = true, every = "6h", keep_days = 7 }
  }

  assert {
    condition     = output.backup_bucket == "test-vaults-123456789012-backup"
    error_message = "the backup bucket should be <bucket>-backup"
  }

  assert {
    condition     = module.backup[0].function_name == "test-backup-lambda"
    error_message = "the copier should be named after the project"
  }

  assert {
    condition     = module.backup[0].schedule_expression == "rate(6 hours)"
    error_message = "every = 6h should schedule rate(6 hours)"
  }
}

# A frequency that is not <n>h or <n>d is refused at plan time.
run "backup_every_rejected" {
  command = plan

  module {
    source = "./modules/s3keepass"
  }

  variables {
    s3_backup = { enabled = true, every = "daily" }
  }

  expect_failures = [var.s3_backup]
}
