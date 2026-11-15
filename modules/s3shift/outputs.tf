output "console_url" {
  description = "The query editor in a browser; the same URL is the host for s3shift.redshift_connector.connect(host=...)"
  value       = module.server.url
}

output "bucket" {
  description = "The catalog, managed tables and large results"
  value       = module.bucket.name
}

output "function_name" {
  value = module.server.function_name
}
