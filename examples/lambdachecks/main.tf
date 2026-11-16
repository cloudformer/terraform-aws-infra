# A minimal lambdachecks deployment. Needs Docker running (the packages are built in AWS's Lambda images).
# export TF_VAR_console_password='a-long-password-16+'
# export TF_VAR_secret_key='a-long-random-string-16+'
# terraform -chdir=examples/lambdachecks init && terraform -chdir=examples/lambdachecks apply

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
  description = "The database's sign-in password (s3rds), 16+ characters."
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Django's SECRET_KEY and the setup key, 16+ characters; keep it stable."
  type        = string
  sensitive   = true
}

module "checks" {
  source  = "cloudformer/infra/aws//modules/lambdachecks" # stable: a released version
  version = "~> 0.2.0"
  # source  = "github.com/cloudformer/terraform-aws-infra//modules/lambdachecks?ref=main" # latest: the main branch, not released yet
  # source  = "../../modules/lambdachecks"                                                # local: this repo's code

  project_name          = "lambdachecks-example"
  console_auth_username = "admin"
  console_auth_password = var.console_password
  secret_key            = var.secret_key
  force_destroy         = true # an example: destroy removes the database too

  # optional, defaults shown
  # lambdachecks_version = "X.Y.Z"        # unset: the lambdachecks release this module version ships with
  # bucket               = null           # <project_name>-db-<account id>
  # console              = true           # s3rds' console at db_url
  # registration_open    = false
  # db_name              = "healthchecks"
  # architecture         = "arm64"
  # memory_size          = 1024
}

output "url" {
  value = module.checks.url
}

output "manage_function" {
  value = module.checks.manage_function
}

output "db_url" {
  value = module.checks.db_url
}
