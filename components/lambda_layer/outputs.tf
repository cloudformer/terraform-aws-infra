output "arn" {
  description = "The layer version ARN, for a function's layers."
  value       = aws_lambda_layer_version.this.arn
}
