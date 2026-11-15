# lambdaflow

Airflow 3 DAG files on Lambda, Step Functions, EventBridge Scheduler, DynamoDB and S3, with a web console at the
Function URL. ≈ $0 when nothing runs; the same DAG files move to MWAA unchanged when you outgrow it. Project:
[cloudformer/lambdaflow](https://github.com/cloudformer/lambdaflow) · part of [IdleFree](https://cloudformer.github.io/).

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

variable "console_password" {
  type      = string
  sensitive = true
}

module "airflow" {
  source  = "cloudformer/infra/aws//modules/lambdaflow"
  version = "~> 0.2.0"

  project_name          = "myairflow"
  console_auth_username = "admin"
  console_auth_password = var.console_password # 16+ characters
  # task_policy_arns    = [aws_iam_policy.tasks.arn] # what your task code may do
}

output "console_url" {
  value = module.airflow.console_url
}

output "dags_folder" {
  value = module.airflow.dags_folder
}
```

```bash
export TF_VAR_console_password='a-long-password-16+'
terraform init && terraform apply
aws s3 cp my_dag.py "$(terraform output -raw dags_folder)"   # or upload it in the console
```

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only): `dags/`, `logs/` (expire after `task_log_days`) | `<project_name>-data-<account id>`, or `bucket` |
| DynamoDB table (on demand): DAGs, runs, task instances, XComs | `<project_name>` |
| Lambda layer: jinja2, tzdata (Linux arm64) | `<project_name>-deps` |
| Lambda worker (arm64, no URL): the only code that imports DAG files and runs tasks | `<project_name>-worker` |
| Step Functions state machine: one execution per DAG run | `<project_name>-run` |
| EventBridge Scheduler group + its role: one schedule per DAG, created by the console | `<project_name>` |
| SQS dead-letter queue: schedules that could not start a run | `<project_name>-schedule-dlq` |
| Lambda console + Function URL (arm64): web console, JSON API, S3 events for `dags/` | `<project_name>-console` |
| IAM roles: console, worker (+ `task_policy_arns`), state machine, scheduler | `<project_name>-console` … |
| CloudWatch log groups, `cloudwatch_log_days` | `/aws/lambda/<project_name>-console`, `-worker` |

The functions run `lambdaflow` from PyPI. `lambdaflow_version` defaults to the release this module was tested
with; set it to move to a newer lambdaflow without waiting for a new module version.

## Requirements

- Terraform ≥ 1.5, AWS provider 6.x, AWS credentials.
- `python3` with `pip` on the machine running Terraform: the code and the layer are built there at plan time.

## Notes

- Task code runs as the worker role: it can read the DAG files and write logs, nothing more. Grant what tasks need
  with `task_policy_arns`; the console can never widen it.
- `force_destroy` defaults to `false`: destroy stops at a bucket that still holds DAG files or logs. Keep your DAGs
  in git, set it to `true`, **apply**, then destroy.
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
