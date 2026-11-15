# A minimal s3shift deployment.
# export TF_VAR_console_password='a-long-password-16+'
# terraform -chdir=examples/s3shift init && terraform -chdir=examples/s3shift apply

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
  description = "Sign-in password, 16+ characters."
  type        = string
  sensitive   = true
}

module "warehouse" {
  source  = "cloudformer/infra/aws//modules/s3shift" # stable: a released version
  version = "~> 0.2.0"
  # source  = "github.com/cloudformer/terraform-aws-infra//modules/s3shift?ref=main" # latest: the main branch, not released yet
  # source  = "../../modules/s3shift"                                                # local: this repo's code

  project_name          = "s3shift-example"
  console_auth_username = "admin"
  console_auth_password = var.console_password
  force_destroy         = true # an example: destroy removes the tables too

  # optional, defaults shown
  # s3shift_version        = "X.Y.Z"  # unset: the s3shift release this module version ships with
  # bucket                 = null     # <project_name>-data-<account id>
  # console                = true
  # function_url_auth      = "NONE"
  # memory_mb              = 3008
  # read_buckets           = []       # your data buckets it may read, e.g. ["my-data-lake"]
  # vpc_subnet_ids         = []       # only for a private RDS (CREATE EXTERNAL SCHEMA)
  # vpc_security_group_ids = []
}

output "console_url" {
  value = module.warehouse.console_url
}

output "bucket" {
  value = module.warehouse.bucket
}
