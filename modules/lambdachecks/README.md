# lambdachecks

[Healthchecks](https://github.com/healthchecks/healthchecks) (cron / scheduled-job monitoring), the official release
unchanged, on Lambda behind a Function URL, with its database on [s3rds](https://github.com/cloudformer/s3rds) (SQLite
on S3) in the same stack. ≈ $0 when idle; small scale (MVP, dev / staging, tens of checks). Project:
[cloudformer/lambdachecks](https://github.com/cloudformer/lambdachecks) · part of [IdleFree](https://cloudformer.github.io/).

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

variable "console_password" {
  type      = string
  sensitive = true
}

variable "secret_key" {
  type      = string
  sensitive = true
}

module "checks" {
  source  = "cloudformer/infra/aws//modules/lambdachecks"
  version = "~> 0.2.0"

  project_name          = "mychecks"
  console_auth_username = "admin"
  console_auth_password = var.console_password # 16+ characters: the database's sign-in
  secret_key            = var.secret_key       # 16+ characters: Django's SECRET_KEY, also the setup key
}

output "url" {
  value = module.checks.url
}
```

```bash
export TF_VAR_console_password='a-long-password-16+'
export TF_VAR_secret_key="$(python3 -c 'import secrets; print(secrets.token_urlsafe(40))')"   # keep it: it must stay stable
terraform init && terraform apply   # first run: builds both architectures in Docker, minutes
```

Then open `url`. Until the first account exists every page is the setup page; each step asks for the setup key
(`secret_key`): **Run migrations** (a few minutes, in the manage function), then **Create the account**. Sign in
with that email and password.

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only): the database, `db/<db_name>.sqlite` | `<project_name>-db-<account id>`, or `bucket` |
| Lambda + Function URL: s3rds' server (python3.12, reserved concurrency 1: one writer), console at `db_url` | `<project_name>-db-lambda` |
| Lambda + Function URL: Healthchecks (python3.13): UI, API, ping URLs, the setup page | `<project_name>-lambda` |
| Lambda, no URL: `manage.py` (15 min, reserved concurrency 1, no retries) | `<project_name>-manage` |
| IAM roles: own log group; s3rds its `db/*.sqlite`; the web function may start the manage function | `<function>-role` |
| CloudWatch log groups, 14 days | `/aws/lambda/<function>` |

The functions run `lambdachecks` from PyPI next to Healthchecks' release and s3rds' released server, built for
`architecture` (arm64 by default; both are built). `lambdachecks_version` defaults to the release this module was
tested with; set it to move to a newer lambdachecks without waiting for a new module version.

## Requirements

- Terraform ≥ 1.5, AWS provider 6.x, AWS credentials.
- `python3` with `pip`, and **Docker running**, on the machine running Terraform: the packages are built at plan
  time inside AWS's Lambda Python images (both architectures; the first build takes minutes). A later plan with the
  same `lambdachecks_version` reuses the build and needs neither Docker nor a download.

## Notes

- `force_destroy` defaults to `false`: `terraform destroy` stops at a bucket that still holds the database. Set it to
  `true`, **apply**, then destroy.
- `manage.py` by hand: `aws lambda invoke --function-name <manage_function> --cli-binary-format raw-in-base64-out
  --payload '{"manage": ["createsuperuser", "--email", "me@example.com", "--password", "..."]}' /dev/stdout`.
- Moving from a deployment whose Lambdas created their own log groups: import them, then apply again —
  `terraform import 'module.<name>.module.server.aws_cloudwatch_log_group.this' /aws/lambda/<project_name>-lambda`
  (likewise `module.manage` / `-manage`, `module.db` / `-db-lambda`).
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
