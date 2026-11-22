output "console_url" {
  description = "The web UI (and its API under /api/); sign in with http_auth or Cloudflare Access."
  value       = module.server.url
}

output "bucket" {
  description = "The queue and the reports: s3://<bucket>/tasks/, s3://<bucket>/reports/<task id>/<host>/."
  value       = module.bucket.name
}

output "codebuild_project" {
  description = "The CodeBuild project: one build per scanner."
  value       = module.scanner.name
}

output "secret_parameters" {
  description = "The SSM SecureStrings of secrets, created holding CHANGE-ME: set each with aws ssm put-parameter --overwrite."
  value       = [for p in aws_ssm_parameter.secret : p.name]
}
