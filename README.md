# terraform-aws-infra

Terraform modules for the Redefine AWS Serverless series. Call one project module with a few variables:
`source = "cloudformer/infra/aws//modules/<project>"`.

| Module | What |
|---|---|
| [s3rds](modules/s3rds) | Serverless MySQL / PostgreSQL / SQLite-compatible database on Lambda + S3 |

Each module's README is its documentation; `examples/<project>` is a minimal deployment.
