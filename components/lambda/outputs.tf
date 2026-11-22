output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "url" {
  description = "null when function_url = false."
  value       = one(aws_lambda_function_url.this[*].function_url)
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "policy" {
  description = "The role's inline policy (JSON)."
  value       = aws_iam_role_policy.this.policy
}
