# terraform-aws-infra — working notes for Claude

The Terraform modules of the **Redefine AWS Serverless** series (github.com/cloudformer), published on the
public Terraform Registry as `cloudformer/infra/aws`. One repository for every project's infrastructure; a
user calls one project module and passes a few variables:

```hcl
module "db" {
  source  = "cloudformer/infra/aws//modules/s3rds"
  version = "~> 0.1"
  project_name          = "myapp"
  console_auth_username = "admin"
  console_auth_password = var.db_password
}
```

## Layout

```
main.tf          empty: the Registry requires a root module; nobody calls it
modules/<p>/     one per project: the public entry, shown on the Registry. Composes components/,
                 pins the project's package (e.g. s3rds[server]==0.3.4). README.md = the usage docs.
components/<c>/  building blocks used by modules/*: s3_bucket, lambda, (dynamodb_table, iam_role … when needed)
examples/<p>/    a minimal call of modules/<p> (how to use it; the smoke test deploys it)
tests/mock/      <p>.tftest.hcl: terraform test with mocked providers, plan only, no AWS
tests/smoke/     <p>.py: run against the deployed examples/<p>
Makefile         test / smoke P=<p> / release V=vX.Y.Z
```

## Principles

1. **People call `modules/<p>` only.** A project module composes components; it holds no resource another
   project would need too. Entries live under `modules/` because the Registry lists only that directory.
2. **Components are building blocks, one AWS service each.** `lambda` bundles what belongs to one function:
   its IAM role and policy, log group (14 days, IAM may write only there), Function URL, concurrency. Other
   services (s3, dynamodb, standalone iam) are separate components. A component is written when the first
   project needs it, not before.
3. **Typed variables with a `description` each**, `validation` where a wrong value would deploy something
   broken or open. The Registry builds the Inputs / Outputs pages from them — no hand-written variable tables.
4. **Defaults are Frank's own setup** (e.g. `force_destroy = true`, `db_ro = true`); others override what
   they need. Required variables are only what has no sensible default (project name, credentials).
5. **No `provider` or `backend` in modules or components** — the caller owns them. Required provider
   versions are declared once per module in `versions.tf`.
6. **`project_name` derives every name** (bucket, functions, roles); names must not collide across
   projects in one account. Least-privilege IAM; destroy must work.
7. **The public surface of `modules/` only grows**: paths, variable names, output names — add, never rename
   or remove; every module shares one version tag, so one break breaks everybody. `components/` may change
   freely (callable, but not promised). A break is Frank's call first.
8. **A project module deploys a released package from PyPI**, never a working tree. Its version is a
   variable (`<project>_version`) whose default is the release this module was tested with; users upgrade
   by setting it, Frank moves the default once a release is proven. The project's own repo keeps its own
   `terraform/` that deploys its working tree for pre-release tests; this repo is distribution.
9. **Docs live in one place**: `modules/<p>/README.md` (the Registry shows the same file). The root README,
   project READMEs, PyPI pages and the org profile only link to it.

## How we work

- Discuss first, build after an explicit go ("开始 / 建吧 / 可以了").
- Frank runs every command (terraform, git, tags, Registry). Claude edits code and gives the commands, with
  `-chdir` / `git -C`, never `cd`.
- English everywhere.
- Version tags are Frank's call; never propose a number.

## Tests

| | mock (`make test`) | smoke (`make smoke P=<p>`) |
|---|---|---|
| Question | is the plan right? (endpoints, names, IAM scope, rejected input, public surface) | does a real deployment work? |
| How | `terraform test` on `tests/mock/`, providers mocked; seconds, no AWS | apply `examples/<p>`, run `tests/smoke/<p>.py`, destroy |
| When | every change; CI on every push / PR to main | before a release, for the projects it touches |
| Scope | always all of `tests/mock/` | changed projects; a changed component smokes every module using it |

- One file per project on each side, same name: `tests/mock/<p>.tftest.hcl`, `tests/smoke/<p>.py`.
- Components are covered through the modules that use them. A component gets its own
  `tests/mock/<c>_component.tftest.hcl` only when a branch of it is used by no module, or it is shared by
  three or more modules.

## Release

1. Change a module or component; for a new package version, move the `<project>_version` default in `modules/<p>`.
2. Commit and push; CI runs the mock tests.
3. `AWS_PROFILE=… TF_VAR_…=… make release V=vX.Y.Z`: mock tests, smoke tests, then tag + push — the Registry
   picks the tag up by webhook.
