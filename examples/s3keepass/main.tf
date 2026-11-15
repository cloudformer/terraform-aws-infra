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

  project_name  = "s3keepass-example"
  force_destroy = true # an example: destroy removes the vaults too

  # sign-in: any method that is on lets a request in; at least one must be on
  http_auth = {
    enabled  = true
    username = "admin"
    password = var.console_password
  }
  cloudflare_auth = {
    enabled = false
    team    = "myteam"    # <team>.cloudflareaccess.com
    aud     = "CHANGE-ME" # the Access application's AUD tag
  }

  # optional, defaults shown
  # s3keepass_version  = "X.Y.Z"  # unset: the s3keepass release this module version ships with
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
