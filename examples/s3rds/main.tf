# A minimal s3rds deployment. Your own project would use the Registry source instead of the path:
#   source  = "cloudformer/infra/aws//modules/s3rds"
#   version = "~> 0.1"
#
#   export TF_VAR_db_password='a-long-password-16+'
#   terraform -chdir=examples/s3rds init && terraform -chdir=examples/s3rds apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-2" # credentials: AWS_PROFILE or the default chain
}

variable "db_password" {
  description = "Database password, 16+ characters."
  type        = string
  sensitive   = true
}

module "db" {
  source = "../../modules/s3rds"

  project_name          = "s3rds-example"
  console_auth_username = "admin"
  console_auth_password = var.db_password

  # optional, defaults shown
  # s3rds_version     = "0.3.4"
  # console           = true
  # function_url_auth = "NONE"
  # db_ro             = true
  # force_destroy     = true
}

output "db_url" {
  value = module.db.db_url
}

output "db_ro_url" {
  value = module.db.db_ro_url
}
