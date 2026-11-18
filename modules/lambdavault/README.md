# lambdavault

HashiCorp Vault, the official binary unchanged, inside a Lambda: data in S3, ≈ $0 when idle. The vault CLI, the
Terraform vault provider, the Vault UI and hvac are the clients; only `VAULT_ADDR` changes. Project:
[cloudformer/lambdavault](https://github.com/cloudformer/lambdavault) · part of [IdleFree](https://cloudformer.github.io/).

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

module "vault" {
  source  = "cloudformer/infra/aws//modules/lambdavault"
  version = "~> 0.2.0"

  project_name = "myvault"
  seal = {
    type = "ssm" # default, free; "kms" = KMS auto-unseal, ≈ $1 a month
    # kms_deletion_window_days = 7   # type = kms only: days a destroyed key can still be recovered (7 to 30)
  }
}

output "vault_addr" {
  value = module.vault.vault_addr
}
```

```bash
terraform init && terraform apply                 # Docker running: apply builds and pushes the Vault image
export VAULT_ADDR=$(terraform output -raw vault_addr)
vault operator init -key-shares=1 -key-threshold=1        # seal = ssm; prints the root token and the unseal key once
# seal = kms:  vault operator init -recovery-shares=1 -recovery-threshold=1
export VAULT_TOKEN=<root token>
vault secrets enable -path=kvv2 kv-v2 && vault kv put kvv2/app password=p
```

The Vault UI is at `<vault_addr>/ui/`. `pip install lambdavault` adds `lambdavault status` (initialized / sealed /
latency).

## The seal

Vault encrypts its data with a key that is itself sealed; after every cold start Vault must be unsealed before it
answers. Two ways, picked by `seal.type`:

| `seal.type` | Cost | How a cold start unseals | `vault operator init` |
|---|---|---|---|
| `ssm` (default) | free | Shamir seal with one key share. The key is an SSM Parameter Store SecureString `/<project_name>/unseal-key` (standard tier, AWS's own `aws/ssm` key). The Vault function's start script reads it and unseals Vault before the first request is let through. | `-key-shares=1 -key-threshold=1`; the proxy writes the key to SSM and unseals the running Vault |
| `kms` | ≈ $1 a month (the key, billed by the hour) | Vault's `awskms` seal: a KMS key `alias/<project_name>-seal` wraps Vault's root key; Vault unseals itself | `-recovery-shares=1 -recovery-threshold=1` |

- **Do not change `seal` on an initialized vault.** The data is sealed one way or the other; switching needs a
  Vault seal migration (`vault operator unseal -migrate`), not an apply. Pick it before the first init.
- Fail closed: if the key cannot be read (parameter missing, no permission) Vault stays sealed and every request
  gets an error; it never opens without the key. Put the key back with
  `aws ssm put-parameter --name /<project_name>/unseal-key --type SecureString --value <Unseal Key 1> --overwrite`.
- With `ssm`, an init with more than one key share or with `-pgp-keys` is refused: the one key must be storable.
  Init still prints the root token and the unseal key once, as Vault always does; keep both.
- The SSM parameter is written by the proxy at init, not by Terraform: the key never enters the Terraform state,
  and `terraform destroy` leaves it (with a bucket that survives `force_destroy = false`, it is what unseals that
  data again). After destroying for good, delete it: `aws ssm delete-parameter --name /<project_name>/unseal-key`.

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only): Vault's storage, encrypted by Vault before it is written | `<project_name>-data-<account id>`, or `bucket` |
| ECR repository: the Vault image (official `hashicorp/vault` + AWS Lambda Web Adapter), arm64 and x86_64 | `<project_name>` |
| Lambda, container image, reserved concurrency 1 (the s3 backend has no lock: one Vault process ever writes), no URL | `<project_name>-lambda` |
| Lambda + Function URL (`VAULT_ADDR`): the proxy, queues concurrent callers for the one Vault (up to 25 s) | `<project_name>-proxy-lambda` |
| IAM roles: own log group; Vault: its bucket + the seal (`ssm:GetParameter` on the one parameter, or the KMS key); proxy: invoke Vault (+ `ssm:PutParameter` on the one parameter) | `<project_name>-lambda-role`, `<project_name>-proxy-role` |
| CloudWatch log groups, 14 days | `/aws/lambda/<project_name>-lambda`, `/aws/lambda/<project_name>-proxy-lambda` |
| `seal = kms` only: KMS key (rotation on, 7-day deletion window) | `alias/<project_name>-seal` |

The image and the proxy come from `lambdavault` on PyPI (`lambdavault/server` is the image's Docker build context,
`lambdavault/proxy` the proxy). `lambdavault_version` defaults to the release this module was tested with; set it
to move to a newer lambdavault without waiting for a new module version. The image tag is the content hash of
the build context: a plan rebuilds nothing unless that changed.

## Backup (optional)

```hcl
  s3_backup = { enabled = true, every = "1d", keep_days = 30 } # every: <n>h or <n>d
```

Snapshots of Vault's whole bucket (a snapshot taken during a write may catch it half done; writes are rare) into `<bucket>-backup`, one folder per snapshot (`<UTC time>/`, e.g. `2026-11-15T080000Z/`),
taken only when something changed or the newest is half of `keep_days` old (`every` is how often that is checked, at most half of `keep_days`), deleted after `keep_days`; no S3 versioning involved. The backup bucket follows `force_destroy`. Restore a
snapshot: `aws s3 sync s3://<bucket>-backup/<snapshot>/ s3://<bucket>/ --exclude "manifest.json"`.
Creates `<bucket>-backup`, a copier Lambda and an EventBridge Scheduler schedule (≈ $0 for small data). Rules and restore in detail: [components/s3_backup](https://github.com/cloudformer/terraform-aws-infra/tree/main/components/s3_backup).

## Requirements

- Terraform ≥ 1.10, AWS provider 6.x, AWS credentials.
- `python3` with `pip` on the machine running Terraform: the release is staged there at plan time.
- **Docker** running on that machine, with `buildx` able to build `linux/arm64` and `linux/amd64` (Docker Desktop
  can; on Linux install QEMU binfmt for the other architecture): `apply` builds both images and pushes them to ECR.
  Docker logs in to ECR with the AWS provider's own credentials (no AWS CLI needed).

## Notes

- The URL is public (`authorization_type = NONE`): Vault's own tokens are the gate, as on a Vault behind a load
  balancer.
- `force_destroy` defaults to `false`: destroy stops at a bucket that still holds Vault's data. Set it to `true`,
  **apply**, then destroy.
- Moving from a deployment whose Lambdas created their own log groups: import them, then apply again —
  `terraform import 'module.<name>.module.vault.aws_cloudwatch_log_group.this' /aws/lambda/<project_name>-lambda` and
  `terraform import 'module.<name>.module.proxy.aws_cloudwatch_log_group.this' /aws/lambda/<project_name>-proxy-lambda`.
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
