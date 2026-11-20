# terraform-aws-infra

Terraform modules for the [IdleFree](https://cloudformer.github.io/) series, published on the Terraform Registry as
`cloudformer/infra/aws`. Call a project with `source = "cloudformer/infra/aws//modules/<project>"`.

| Project | What |
|---|---|
| [s3rds](modules/s3rds) | Serverless MySQL / PostgreSQL / SQLite-compatible database on Lambda + S3 |
| [s3keepass](modules/s3keepass) | KeePass vaults (.kdbx) on S3 with a web UI; decrypted only in the browser |
| [s3shift](modules/s3shift) | Serverless Redshift: Redshift SQL on DuckDB in a Lambda, over your own S3 and RDS data |
| [lambdaflow](modules/lambdaflow) | Serverless Airflow: Airflow 3 DAG files on Lambda, Step Functions, EventBridge Scheduler and DynamoDB |
| [lambdachecks](modules/lambdachecks) | Healthchecks (cron job monitoring), unchanged, on Lambda with its database on s3rds |
| [lambdavault](modules/lambdavault) | Serverless HashiCorp Vault: the official binary in a Lambda, data in S3, unseal key in SSM (or KMS) |

## Layout

```
modules/
  <project>/           published module (server side): what users call
examples/
  <project>/           how a user calls modules/<project> (client side)
components/
  <project part>/      a part the projects are built from, reused across projects
tests/
  mock/                checks every project's plan without AWS, on every push
  smoke/               deploys a project for real, then destroys it, before a release
  unit/                a component's own code against a fake S3 (s3_backup), no AWS
.github/workflows/     runs the mock tests on GitHub
```

Release: `make release PROJECT=<project> VERSION=vX.Y.Z` runs both tests, then pushes the tag; the Registry publishes that version.

## Planned

- **cloudflare_front** (TODO): a separate module that puts a Function URL behind a domain on Cloudflare: the proxied DNS
  record, a Cloudflare Access application and policy (who may sign in), and a Worker route + variable that forwards
  the hostname to the Function URL (the free plan cannot rewrite the Host header otherwise). Its output feeds a
  project's `cloudflare_auth`, and a new Function URL after a destroy / apply updates the Worker with it. Separate so
  that nobody who skips Cloudflare needs the Cloudflare provider or a token.

MIT, see [LICENSE](LICENSE).
