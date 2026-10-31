# Mock tests for modules/s3rds: plan only, every provider mocked — no AWS account, no pip build.
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

# Defaults: a read/write and a read-only endpoint, bucket named <project>-db-<account>.
run "defaults" {
  command = plan

  module {
    source = "./modules/s3rds"
  }

  assert {
    condition     = length(module.endpoint) == 2
    error_message = "defaults should deploy the rw and ro endpoints"
  }

  assert {
    condition     = module.bucket.name == "test-db-123456789012"
    error_message = "bucket name should be <project_name>-db-<account id>"
  }
}

# db_ro = false: the read/write endpoint only, db_ro_url is null.
run "no_read_only_endpoint" {
  command = plan

  module {
    source = "./modules/s3rds"
  }

  variables {
    db_ro = false
  }

  assert {
    condition     = keys(module.endpoint) == ["rw"]
    error_message = "db_ro = false should deploy the rw endpoint only"
  }

  assert {
    condition     = output.db_ro_url == null
    error_message = "db_ro_url should be null with db_ro = false"
  }
}

# A password under 16 characters is refused at plan time.
run "short_password_rejected" {
  command = plan

  module {
    source = "./modules/s3rds"
  }

  variables {
    console_auth_password = "short"
  }

  expect_failures = [var.console_auth_password]
}
