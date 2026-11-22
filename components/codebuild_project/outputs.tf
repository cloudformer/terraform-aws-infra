output "name" {
  value = aws_codebuild_project.this.name
}

output "arn" {
  value = aws_codebuild_project.this.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "policy" {
  description = "The role's inline policy (JSON)."
  value       = aws_iam_role_policy.this.policy
}

output "environment" {
  description = "What every build runs on: type, compute_type, image."
  value       = { type = local.type[var.architecture], compute_type = var.compute_type, image = var.image }
}

output "concurrent_build_limit" {
  value = aws_codebuild_project.this.concurrent_build_limit
}

output "timeout_minutes" {
  value = aws_codebuild_project.this.build_timeout
}

output "variables" {
  description = "The environment variables every build gets."
  value       = var.environment
}
