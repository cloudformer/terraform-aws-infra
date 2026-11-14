# A minimal s3keepass deployment.
# export TF_VAR_console_password='a-long-password-16+'
# terraform -chdir=examples/s3keepass init && terraform -chdir=examples/s3keepass apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-2" # credentials: AWS_PROFILE or the default chain
}

variable "console_password" {
  description = "Web UI sign-in password, 16+ characters."
  type        = string
  sensitive   = true
}

module "keepass" {
  source  = "cloudformer/infra/aws//modules/s3keepass" # stable: a released version
  version = "~> 0.1"
  # source  = "github.com/cloudformer/terraform-aws-infra//modules/s3keepass?ref=main" # latest: the main branch, not released yet
  # source  = "../../modules/s3keepass"                                                # local: this repo's code

  project_name          = "s3keepass-example"
  console_auth_username = "admin"
  console_auth_password = var.console_password
  force_destroy         = true # an example: destroy removes the vaults too

  # optional, defaults shown
  # s3keepass_version  = "0.1.1"
  # bucket             = null   # <project_name>-vaults-<account id>
  # console            = true
  # function_url_auth  = "NONE"
  # keep_versions      = 5
  # log_retention_days = 90
  # architecture       = "arm64"
  # custom_template    = { kdf = { unlock_ms = 3000 }, recycle_bin = true }   # advanced: only these fields change
}

output "console_url" {
  value = module.keepass.console_url
}

output "bucket" {
  value = module.keepass.bucket
}
