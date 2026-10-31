# terraform-aws-infra

Terraform modules for the Redefine AWS Serverless series, published on the Terraform Registry as
`cloudformer/infra/aws`. Call a project with `source = "cloudformer/infra/aws//modules/<project>"`.

| Project | What |
|---|---|
| [s3rds](modules/s3rds) | Serverless MySQL / PostgreSQL / SQLite-compatible database on Lambda + S3 |

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
.github/workflows/     runs the mock tests on GitHub
```

Release: `make release PROJECT=<project> VERSION=vX.Y.Z` runs both tests, then pushes the tag; the Registry publishes that version.
