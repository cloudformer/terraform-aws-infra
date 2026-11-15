# Mock tests for modules/lambdaflow: plan only, every provider mocked — no AWS account, no pip build.
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

# Defaults: names from project_name; the console has a URL, the worker none; task logs expire after 30 days.
run "defaults" {
  command = plan

  module {
    source = "./modules/lambdaflow"
  }

  assert {
    condition     = module.bucket.name == "test-data-123456789012"
    error_message = "bucket name should be <project_name>-data-<account id>"
  }

  assert {
    condition     = module.console.function_name == "test-console" && module.worker.function_name == "test-worker"
    error_message = "functions should be <project_name>-console and <project_name>-worker"
  }

  assert {
    condition     = module.table.name == "test" && module.schedules.name == "test"
    error_message = "table and scheduler group should be <project_name>"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.logs.rule[0].expiration[0].days == 30
    error_message = "task logs should expire after task_log_days (30)"
  }

  assert {
    condition     = aws_s3_bucket_notification.dags.lambda_function[0].filter_prefix == "dags/"
    error_message = "DAG files under dags/ should reach the console"
  }
}

# A task timeout beyond Lambda's 900 s is refused at plan time.
run "task_timeout_rejected" {
  command = plan

  module {
    source = "./modules/lambdaflow"
  }

  variables {
    task_timeout = 1200
  }

  expect_failures = [var.task_timeout]
}

# A password under 16 characters is refused at plan time.
run "short_password_rejected" {
  command = plan

  module {
    source = "./modules/lambdaflow"
  }

  variables {
    console_auth_password = "short"
  }

  expect_failures = [var.console_auth_password]
}
