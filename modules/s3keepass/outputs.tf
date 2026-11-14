output "console_url" {
  description = "The web UI (and the vault API under /api/); sign in with console_auth_username / console_auth_password."
  value       = module.server.url
}

output "bucket" {
  description = "The bucket holding the vaults: s3://<bucket>/keepass/[<folder>/]<vault>.kdbx."
  value       = module.bucket.name
}
