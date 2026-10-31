output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "url" {
  value = aws_lambda_function_url.this.function_url
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
