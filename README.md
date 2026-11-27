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
| [lambdazap](modules/lambdazap) | OWASP ZAP scans of your own sites from a web UI; scanners are fresh CodeBuild instances you start and shut down |
| [lambdakali](modules/lambdakali) | A serverless Kali command console; start a scanner, type shell commands, they run on a fresh CodeBuild instance |

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

## Bootstrap (two things created by hand, on purpose)

Everything in this repo is Terraform — except two bootstrap items that deliberately live
outside it. Do not "adopt" them into a module later: being outside is the design.

**1. The state bucket** — Terraform cannot manage its own filing cabinet (the bucket that
holds the state would need its state held somewhere). Created once per account, versioned
(the time machine for every deployment's state):

```sh
bucket_name=<your-tfstate-bucket>
region=<your-region>
profile=<your-aws-profile>

aws --profile $profile --region $region s3 mb s3://$bucket_name
aws --profile $profile --region $region s3api put-public-access-block --bucket $bucket_name --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws --profile $profile --region $region s3api put-bucket-versioning --bucket $bucket_name --versioning-configuration Status=Enabled
aws --profile $profile --region $region s3api put-bucket-encryption --bucket $bucket_name --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws --profile $profile --region $region s3api put-bucket-lifecycle-configuration --bucket $bucket_name --lifecycle-configuration '{"Rules":[
  {"ID":"expire-old-state-versions","Status":"Enabled","Filter":{},
   "NoncurrentVersionExpiration":{"NoncurrentDays":90}},
  {"ID":"abort-incomplete-uploads","Status":"Enabled","Filter":{},
   "AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'
```

Private (all public access blocked), versioned (every old state kept 90 days — the undo
button), encrypted at rest, incomplete uploads swept. Backends set `use_lockfile = true`
(Terraform ≥ 1.10): concurrent applies lock through S3 itself, no DynamoDB table.

Every deployment directory points at it with a hardcoded `backend "s3"` block (backend config
cannot use variables — hardcoding is both forced and honest).

**2. The machines' Cloudflare service token** — one shared token that lets fleet machines
through the Access door in front of the vault. If Terraform created the parameter, the token's
value would land in the state file; by hand it never touches Terraform:

```sh
ssm_path=/idlefree/cf-service-token
token=<the service token from the Cloudflare Zero Trust panel>
region=<your-region>
profile=<your-aws-profile>

aws --profile $profile --region $region ssm put-parameter --name $ssm_path --type SecureString --value "$token" --overwrite
```

Rotation = rerun that command (about yearly). Modules only ever receive the parameter's PATH
as a plain string (`cf_token_parameter`), pass it to the function's env and grant the role
read on exactly that parameter; the program resolves it at runtime.

## Planned

- **cloudflare_front** (TODO): a separate module that puts a Function URL behind a domain on Cloudflare: the proxied DNS
  record, a Cloudflare Access application and policy (who may sign in), and a Worker route + variable that forwards
  the hostname to the Function URL (the free plan cannot rewrite the Host header otherwise). Its output feeds a
  project's `cloudflare_auth`, and a new Function URL after a destroy / apply updates the Worker with it. Separate so
  that nobody who skips Cloudflare needs the Cloudflare provider or a token.

MIT, see [LICENSE](LICENSE).
