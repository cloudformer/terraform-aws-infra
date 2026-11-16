output "url" {
  description = "Healthchecks: open in a browser (the setup page until the first account exists); ping URLs are <url>ping/<uuid>"
  value       = module.server.url
}

output "manage_function" {
  description = "aws lambda invoke --function-name <this> --payload '{\"manage\": [...]}' runs manage.py"
  value       = module.manage.function_name
}

output "db_url" {
  description = "s3rds' console: Healthchecks' tables and rows (sign in with console_auth_username / console_auth_password)"
  value       = module.db.url
}

output "bucket" {
  description = "The database file: db/<db_name>.sqlite"
  value       = module.bucket.name
}

output "function_name" {
  description = "The web function"
  value       = module.server.function_name
}
