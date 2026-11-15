# s3keepass

KeePass vaults (`.kdbx`) on your own S3, opened in a web UI served by a Lambda Function URL. Decryption happens only
in the browser; the server only moves ciphertext. ≈ $0 when idle, and KeePassXC still opens the same file.
Project: [cloudformer/s3keepass](https://github.com/cloudformer/s3keepass) · part of [IdleFree](https://cloudformer.github.io/).

![architecture](https://raw.githubusercontent.com/cloudformer/s3keepass/main/docs/architecture.svg)

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

variable "console_password" {
  type      = string
  sensitive = true
}

module "keepass" {
  source  = "cloudformer/infra/aws//modules/s3keepass"
  version = "~> 0.2.0"

  project_name = "mykeepass"

  http_auth = {
    enabled  = true
    username = "admin"
    password = var.console_password # 16+ characters
  }
  cloudflare_auth = {
    enabled = false
    team    = "myteam"
    aud     = "CHANGE-ME"
  }
}

output "console_url" {
  value = module.keepass.console_url
}
```

```bash
export TF_VAR_console_password='a-long-password-16+'
terraform init && terraform apply
```

Open `console_url`, sign in with the user / password above, then create a vault or upload a `.kdbx` from KeePassXC.
Each vault has its own master password (and optional key file), which never leaves the browser.

## Sign-in: password, Cloudflare Access, or both

Two methods, each `enabled` true or false; a request passes when any method that is on accepts it, and plan stops
when none is on. Turning one off keeps its other fields, so turning it on again is one word.

| | `http_auth` | `cloudflare_auth` |
|---|---|---|
| How | user + password (HTTP Basic); the page asks for them | the JWT Cloudflare Access adds in front of the URL |
| Fields | `username`, `password` (16+) | `team` (`<team>.cloudflareaccess.com`), `aud` (the Access application's AUD tag) |
| Identity in access records | the user | the email |

Moving to Cloudflare: turn both on, check the Cloudflare address works, then turn `http_auth` off. With Cloudflare
alone the Function URL opened directly serves nothing, the page included: the Lambda checks the JWT's signature
against the team's public keys, its `aud`, issuer and expiry.

Cloudflare side: an Access application for your hostname (its policy decides who may sign in), and that hostname
forwarding to the Function URL with the Host header set to the Function URL's host (a Worker, or an Origin Rule).

## Advanced settings: the new-vault template

New vaults follow `base_template.json`, shipped in the s3keepass package: Argon2id 128 MiB × 2 lanes, passes tuned
on the creating device until one unlock takes ≥ 2 s; AES-256; no groups or extra fields; no entry history; no
recycle bin. `custom_template` overrides only the fields you set (`kdf` field by field); the rest stays the base:

```hcl
  custom_template = {
    kdf         = { unlock_ms = 3000 } # memory_mib and parallelism stay 128 / 2
    recycle_bin = true
  }
```

It applies to vaults created from then on; an existing vault takes new KDF settings when its master key is changed.

## What it creates

| Resource | Name |
|---|---|
| S3 bucket (private, SSE-S3, TLS only, versioned) | `<project_name>-vaults-<account id>`, or `bucket` |
| Lifecycle: newest `keep_versions` old versions per vault; access records expire after `log_retention_days` | |
| Custom template (`{}` when unset) | `s3://<bucket>/config/custom_template.json` |
| Lambda + Function URL (arm64) | `<project_name>-lambda` |
| IAM role: its own log group, `keepass/*.kdbx`, `log/*`, the custom template | `<project_name>-lambda-role` |
| CloudWatch log group, 14 days | `/aws/lambda/<project_name>-lambda` |

The function runs `s3keepass` from PyPI. `s3keepass_version` defaults to the release this module was tested with;
set it to move to a newer s3keepass without waiting for a new module version.

## Requirements

- Terraform ≥ 1.9, AWS provider 6.x, AWS credentials.
- `python3` with `pip` on the machine running Terraform: the Lambda package is built there at plan time.

## Notes

- `force_destroy` defaults to `false`: `terraform destroy` stops at a bucket that still holds vaults. Download
  what you want to keep, set it to `true`, **apply**, then destroy — destroy uses the value in the state, so
  setting it and destroying right away still stops.
- Moving from a deployment whose Lambda created its own log group (`logs:CreateLogGroup`): apply stops with
  `ResourceAlreadyExistsException` for `/aws/lambda/<project_name>-lambda`. Take it over, then apply again:
  `terraform import 'module.<name>.module.server.aws_cloudwatch_log_group.this' /aws/lambda/<project_name>-lambda`.
- `project_name` must be unique per AWS account; it names every resource.
- 0.2.0 replaced `console_auth_username` / `console_auth_password` with `http_auth = { enabled = true, username,
  password }`; the deployed resources stay the same.
- Inputs and outputs: see the Inputs / Outputs tabs on the Registry.
