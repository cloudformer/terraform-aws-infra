# Mock tests for modules/lambdachecks: plan only, every provider mocked — no AWS account, no Docker build.
# Run from the repo root: make test

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
}

mock_provider "external" {
  override_during = plan

  mock_data "external" {
    defaults = {
      result = {
        "server-arm64" = "/mock/server-arm64", "server-x86_64" = "/mock/server-x86_64"
        "db-arm64"     = "/mock/db-arm64", "db-x86_64" = "/mock/db-x86_64"
      }
    }
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
  secret_key            = "a-secret-key-of-16+chars"
}

# Defaults: bucket <project>-db-<account>, functions <project>-lambda / -manage / -db-lambda, the existing
# policy names, the web function may start only the manage function, no retries of a failed migrate.
run "defaults" {
  command = plan

  module {
    source = "./modules/lambdachecks"
  }

  assert {
    condition     = module.bucket.name == "test-db-123456789012"
    error_message = "bucket name should be <project_name>-db-<account id>"
  }

  assert {
    condition     = module.server.function_name == "test-lambda" && module.manage.function_name == "test-manage" && module.db.function_name == "test-db-lambda"
    error_message = "functions should be <project_name>-lambda, -manage, -db-lambda"
  }

  assert {
    condition     = module.server.role_name == "test-lambda-role" && module.db.role_name == "test-db-lambda-role"
    error_message = "roles should be <function>-role"
  }

  assert {
    condition     = local.manage_arn == "arn:aws:lambda:us-east-2:123456789012:function:test-manage"
    error_message = "the web function's policy should name the manage function"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.manage.maximum_retry_attempts == 0
    error_message = "a failed migrate should not be retried"
  }

  assert {
    condition     = local.env.DB_NAME == "healthchecks" && local.env.REGISTRATION_OPEN == "False"
    error_message = "defaults: database healthchecks, registration closed"
  }
}

# bucket set: that name, nothing derived (an existing deployment keeps its database).
run "bucket_override" {
  command = plan

  module {
    source = "./modules/lambdachecks"
  }

  variables {
    bucket = "my-checks-db"
  }

  assert {
    condition     = module.bucket.name == "my-checks-db"
    error_message = "bucket should be used as given"
  }
}

# A password under 16 characters is refused at plan time.
run "short_password_rejected" {
  command = plan

  module {
    source = "./modules/lambdachecks"
  }

  variables {
    console_auth_password = "short"
  }

  expect_failures = [var.console_auth_password]
}

# An architecture Lambda does not have is refused at plan time.
run "bad_architecture_rejected" {
  command = plan

  module {
    source = "./modules/lambdachecks"
  }

  variables {
    architecture = "arm32"
  }

  expect_failures = [var.architecture]
}
