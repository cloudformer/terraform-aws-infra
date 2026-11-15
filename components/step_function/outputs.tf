output "arn" {
  value = aws_sfn_state_machine.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
