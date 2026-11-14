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
  project_name          = "test"
  console_auth_username = "admin"
  console_auth_password = "a-password-of-16+chars"
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
    console_auth_password = "short"
  }

  expect_failures = [var.console_auth_password]
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
