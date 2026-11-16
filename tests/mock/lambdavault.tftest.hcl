# Mock tests for modules/lambdavault: plan only — no AWS account, no pip build, no Docker.
# Run from the repo root: make test
#
# The aws provider is the real one with fake credentials and every check off, not a mock_provider: the module
# declares an ephemeral resource (the ECR login, count 0 here with build_image = false), and mock providers refuse
# any configuration with one. Planning new resources calls no AWS API; the two data sources are overridden.
provider "aws" {
  region                      = "us-east-2"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.me
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2" }
}

# s3_backup on: its scheduler group reads the account too
override_data {
  target = module.backup[0].module.scheduler.data.aws_caller_identity.me
  values = { account_id = "123456789012" }
}

# a real provider leaves the repository URL unknown at plan time: give it, so the image reference can be checked
override_resource {
  target          = module.ecr.aws_ecr_repository.this
  override_during = plan
  values          = { repository_url = "123456789012.dkr.ecr.us-east-2.amazonaws.com/test" }
}

mock_provider "external" {
  override_during = plan

  mock_data "external" {
    defaults = { result = { server = "/mock/server", proxy = "/mock/proxy", tag = "0123456789abcdef" } }
  }
}

mock_provider "archive" {
  override_during = plan

  mock_data "archive_file" {
    defaults = { output_path = "/mock/out.zip", output_base64sha256 = "bW9jaw==" }
  }
}

variables {
  project_name = "test"
  build_image  = false # no Docker, no ECR login in a mock test
}

# Defaults: names from project_name; seal = ssm, so no KMS key, the unseal key's SSM parameter is named.
run "defaults" {
  command = plan

  module {
    source = "./modules/lambdavault"
  }

  assert {
    condition     = module.bucket.name == "test-data-123456789012"
    error_message = "bucket name should be <project_name>-data-<account id>"
  }

  assert {
    condition     = length(module.bucket.versioning_ids) == 0
    error_message = "Vault's bucket should not be versioned (Vault never reads old versions; s3_backup is the safety net)"
  }

  assert {
    condition     = module.vault.function_name == "test-lambda" && module.proxy.function_name == "test-proxy-lambda"
    error_message = "functions should be <project_name>-lambda (Vault) and <project_name>-proxy-lambda (the URL)"
  }

  assert {
    condition     = module.vault.role_name == "test-lambda-role" && module.proxy.role_name == "test-proxy-role"
    error_message = "roles should be <project_name>-lambda-role and <project_name>-proxy-role"
  }

  assert {
    condition     = module.ecr.name == "test"
    error_message = "the ECR repository should be <project_name>"
  }

  assert {
    condition     = length(module.seal) == 0 && output.kms_key_id == null
    error_message = "seal = ssm (the default) should create no KMS key"
  }

  assert {
    condition     = output.unseal_key_parameter == "/test/unseal-key"
    error_message = "seal = ssm: the unseal key should be the SSM parameter /<project_name>/unseal-key"
  }

  assert {
    condition     = module.image.image == "123456789012.dkr.ecr.us-east-2.amazonaws.com/test:0123456789abcdef"
    error_message = "the image tag should be the content hash build.py reports"
  }
}

# seal = kms: one KMS key, alias/<project_name>-seal; no SSM parameter.
run "seal_kms" {
  command = plan

  module {
    source = "./modules/lambdavault"
  }

  variables {
    seal = { type = "kms" }
  }

  assert {
    condition     = length(module.seal) == 1
    error_message = "seal = kms should create one KMS key"
  }

  assert {
    condition     = module.seal[0].alias == "alias/test-seal"
    error_message = "the KMS key's alias should be alias/<project_name>-seal"
  }

  assert {
    condition     = output.unseal_key_parameter == null
    error_message = "seal = kms keeps nothing in SSM"
  }
}

# bucket set: that name, nothing derived (an existing deployment keeps its data).
run "bucket_override" {
  command = plan

  module {
    source = "./modules/lambdavault"
  }

  variables {
    bucket = "my-vault"
  }

  assert {
    condition     = module.bucket.name == "my-vault"
    error_message = "bucket should be used as given"
  }
}

# Any other seal is refused at plan time.
run "invalid_seal_rejected" {
  command = plan

  module {
    source = "./modules/lambdavault"
  }

  variables {
    seal = { type = "shamir" }
  }

  expect_failures = [var.seal]
}

# s3_backup off (the default): no backup bucket, no copier, no schedule.
run "backup_off" {
  command = plan

  module {
    source = "./modules/lambdavault"
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
    source = "./modules/lambdavault"
  }

  variables {
    s3_backup = { enabled = true, every = "6h", keep_days = 7 }
  }

  assert {
    condition     = output.backup_bucket == "test-data-123456789012-backup"
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
    source = "./modules/lambdavault"
  }

  variables {
    s3_backup = { enabled = true, every = "daily" }
  }

  expect_failures = [var.s3_backup]
}
