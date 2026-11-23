output "console_url" {
  description = "The ztna console (Function URL): open it, sign in, start a jump, connect."
  value       = module.server.url
}

output "bucket" {
  description = "The lease bucket."
  value       = module.bucket.name
}

output "launch_template_id" {
  description = "The launch template every jump is launched from."
  value       = aws_launch_template.jump.id
}

output "jump_role_arn" {
  description = "The IAM role every jump runs with (SSM + self-terminate)."
  value       = aws_iam_role.jump.arn
}
