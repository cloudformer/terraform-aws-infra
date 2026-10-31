# s3rds

A serverless MySQL / PostgreSQL / SQLite-compatible database on AWS Lambda and Amazon S3: each database is one
SQLite file on S3, a Lambda Function URL is the endpoint, and it costs ≈ $0 when idle.
Project: [cloudformer/s3rds](https://github.com/cloudformer/s3rds).

![architecture](https://raw.githubusercontent.com/cloudformer/s3rds/main/docs/architecture.svg)

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

variable "db_password" {
  type      = string
  sensitive = true
}

module "db" {
  source  = "cloudformer/infra/aws//modules/s3rds"
  version = "~> 0.1"

  project_name          = "myapp"
  console_auth_username = "admin"
  console_auth_password = var.db_password # 16+ characters
}

output "db_url" {
  value = module.db.db_url
}
```

```bash
export TF_VAR_db_password='a-long-password-16+'
terraform init && terraform apply
```

Open `db_url` in a browser for the web console (sign in with the user / password above).

## Connect

```python
# pip install "s3rds[mysql]"
from s3rds import pymysql

conn = pymysql.connect(host="xxxx.lambda-url.us-east-2.on.aws",   # db_url
                       user="admin", password="...", database="blog")
```

PostgreSQL, SQLite, SQLAlchemy and Django: see the [s3rds README](https://github.com/cloudformer/s3rds#readme).

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only) | `<project_name>-db-<account id>` |
| Lambda + Function URL, read/write (reserved concurrency 1) | `<project_name>-db-lambda` |
| Lambda + Function URL, read-only (`db_ro = true`) | `<project_name>-db-ro-lambda` |
| IAM role per function: its own log group + `db/*.sqlite` (read-only: GetObject only) | `<function>-role` |
| CloudWatch log group per function, 14 days | `/aws/lambda/<function>` |

The functions run `s3rds[server]` from PyPI. `s3rds_version` defaults to the release this module was tested
with; set it to move to a newer s3rds without waiting for a new module version.

## Requirements

- Terraform ≥ 1.5, AWS provider 6.x, AWS credentials.
- `python3` with `pip` on the machine running Terraform: the Lambda package is built there at plan time.

## Notes

- `force_destroy` defaults to `true`: `terraform destroy` deletes the databases too. Set `false` to keep them.
- `project_name` must be unique per AWS account; it names every resource.
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
