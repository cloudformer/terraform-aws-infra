output "db_url" {
  description = "The database endpoint (host= for connect()); open it in a browser for the web console."
  value       = module.endpoint["rw"].url
}

output "db_ro_url" {
  description = "Read-only endpoint: unlimited concurrency for read-heavy code (writes get 403); null with db_ro = false."
  value       = var.db_ro ? module.endpoint["ro"].url : null
}

output "db_bucket" {
  description = "The bucket holding the databases."
  value       = module.bucket.name
}

output "db_prefix" {
  description = "Database file prefix: s3://<db_bucket>/<db_prefix><database>.sqlite"
  value       = local.prefix
}
