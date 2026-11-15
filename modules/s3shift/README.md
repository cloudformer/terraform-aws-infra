# s3shift

Redshift SQL on DuckDB inside a Lambda, directly over your S3 and RDS data, with a query-editor console at the
Function URL. ≈ $0 when nobody queries; the client is `s3shift.redshift_connector`, the same API as Redshift's
`redshift_connector`. Project: [cloudformer/s3shift](https://github.com/cloudformer/s3shift) · part of
[IdleFree](https://cloudformer.github.io/).

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

variable "console_password" {
  type      = string
  sensitive = true
}

module "warehouse" {
  source  = "cloudformer/infra/aws//modules/s3shift"
  version = "~> 0.2.0"

  project_name          = "mywarehouse"
  console_auth_username = "admin"
  console_auth_password = var.console_password # 16+ characters
  read_buckets          = ["my-data-lake"]     # your data it may read (external tables, COPY)
}

output "console_url" {
  value = module.warehouse.console_url
}
```

```bash
export TF_VAR_console_password='a-long-password-16+'
terraform init && terraform apply
pip install s3shift
```

```python
from s3shift import redshift_connector
conn = redshift_connector.connect(host="<console_url host>", database="dev", user="admin", password="...")
```

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only): catalog, managed tables (Parquet), large results (expire after a day) | `<project_name>-data-<account id>`, or `bucket` |
| Lambda layer: DuckDB, pymysql, psycopg2 (Linux x86_64 wheels) | `<project_name>-deps` |
| Lambda + Function URL (x86_64, 15 min, 10 GB /tmp) | `<project_name>-lambda` |
| IAM role: its own log group, its bucket, `read_buckets` read-only | `<project_name>-lambda-role` |
| CloudWatch log group, 14 days | `/aws/lambda/<project_name>-lambda` |

The function runs `s3shift` from PyPI; the layer holds the pins in its `server/requirements.txt`.
`s3shift_version` defaults to the release this module was tested with; set it to move to a newer s3shift without
waiting for a new module version.

## Requirements

- Terraform ≥ 1.5, AWS provider 6.x, AWS credentials.
- `python3` with `pip` on the machine running Terraform: the code and the layer are built there at plan time.

## Notes

- `force_destroy` defaults to `false`: `terraform destroy` stops at a bucket that still holds tables. `UNLOAD` what
  you want to keep, set it to `true`, **apply**, then destroy.
- A private RDS (`CREATE EXTERNAL SCHEMA ... FROM POSTGRES | MYSQL`): set `vpc_subnet_ids` and
  `vpc_security_group_ids`; the Lambda then needs an S3 gateway endpoint (or NAT) to reach S3.
- Moving from a deployment whose Lambda created its own log group: import it, then apply again —
  `terraform import 'module.<name>.module.server.aws_cloudwatch_log_group.this' /aws/lambda/<project_name>-lambda`.
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
