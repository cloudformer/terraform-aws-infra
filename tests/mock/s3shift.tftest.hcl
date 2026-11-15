# Mock tests for modules/s3shift: plan only, every provider mocked — no AWS account, no pip build.
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
    defaults = { result = { code = "/mock/code", layer = "/mock/layer" } }
  }
}

mock_provider "archive" {
  override_during = plan

  mock_data "archive_file" {
    defaults = { output_path = "/mock/out.zip", output_base64sha256 = "bW9jaw==" }
  }
}

variables {
  project_name          = "test"
  console_auth_username = "admin"
  console_auth_password = "a-password-of-16+chars"
}

# Defaults: bucket <project>-data-<account>, function <project>-lambda, results/ expire after a day.
run "defaults" {
  command = plan

  module {
    source = "./modules/s3shift"
  }

  assert {
    condition     = module.bucket.name == "test-data-123456789012"
    error_message = "bucket name should be <project_name>-data-<account id>"
  }

  assert {
    condition     = module.server.function_name == "test-lambda"
    error_message = "function name should be <project_name>-lambda"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.data.rule[0].expiration[0].days == 1
    error_message = "large results should expire after a day"
  }
}

# bucket set: that name, nothing derived (an existing deployment keeps its tables).
run "bucket_override" {
  command = plan

  module {
    source = "./modules/s3shift"
  }

  variables {
    bucket = "my-warehouse"
  }

  assert {
    condition     = module.bucket.name == "my-warehouse"
    error_message = "bucket should be used as given"
  }
}

# A password under 16 characters is refused at plan time.
run "short_password_rejected" {
  command = plan

  module {
    source = "./modules/s3shift"
  }

  variables {
    console_auth_password = "short"
  }

  expect_failures = [var.console_auth_password]
}
