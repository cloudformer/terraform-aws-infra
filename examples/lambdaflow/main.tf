# A minimal lambdaflow deployment.
# export TF_VAR_console_password='a-long-password-16+'
# terraform -chdir=examples/lambdaflow init && terraform -chdir=examples/lambdaflow apply

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

module "airflow" {
  source  = "cloudformer/infra/aws//modules/lambdaflow" # stable: a released version
  version = "~> 0.2.0"
  # source  = "github.com/cloudformer/terraform-aws-infra//modules/lambdaflow?ref=main" # latest: the main branch, not released yet
  # source  = "../../modules/lambdaflow"                                                # local: this repo's code

  project_name          = "lambdaflow-example"
  console_auth_username = "admin"
  console_auth_password = var.console_password
  force_destroy         = true # an example: destroy removes the DAG files and logs too

  # optional, defaults shown
  # lambdaflow_version  = "X.Y.Z"  # unset: the lambdaflow release this module version ships with
  # bucket              = null     # <project_name>-data-<account id>
  # console             = true
  # function_url_auth   = "NONE"
  # task_policy_arns    = []       # what task code may do, e.g. read your data bucket
  # task_env            = {}       # AIRFLOW_VAR_* / AIRFLOW_CONN_*
  # task_timeout        = 900
  # worker_memory       = 1024
  # max_parallel_tasks  = 10
  # paused_at_creation  = true
  # task_log_days       = 30
  # cloudwatch_log_days = 14
}

output "console_url" {
  value = module.airflow.console_url
}

output "dags_folder" {
  value = module.airflow.dags_folder
}
