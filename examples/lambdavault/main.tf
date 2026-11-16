# A minimal lambdavault deployment. Docker must be running: apply builds and pushes the Vault image.
# terraform -chdir=examples/lambdavault init && terraform -chdir=examples/lambdavault apply

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-2" # credentials: AWS_PROFILE or the default chain
}

module "vault" {
  source  = "cloudformer/infra/aws//modules/lambdavault" # stable: a released version
  version = "~> 0.2.0"
  # source  = "github.com/cloudformer/terraform-aws-infra//modules/lambdavault?ref=main" # latest: the main branch, not released yet
  # source  = "../../modules/lambdavault"                                                # local: this repo's code

  project_name  = "lambdavault-example"
  force_destroy = true # an example: destroy removes Vault's data too

  # how Vault unseals at a cold start; fixed at the first init (changing it later needs a seal migration)
  seal = {
    type                     = "ssm" # ssm = free (unseal key in SSM Parameter Store) | kms = ≈ $1 / month (KMS auto-unseal)
    kms_deletion_window_days = 7     # type = kms only: days a destroyed key can still be recovered (7 to 30)
  }

  # optional, defaults shown
  # lambdavault_version = "X.Y.Z"  # unset: the lambdavault release this module version ships with
  # bucket              = null     # <project_name>-data-<account id>
  # architecture        = "arm64"  # or x86_64; both images are built
  # memory_size         = 1024
}

output "vault_addr" {
  value = module.vault.vault_addr
}

output "unseal_key_parameter" {
  value = module.vault.unseal_key_parameter
}

output "function_name" {
  value = module.vault.function_name
}
