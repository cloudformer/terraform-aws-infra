output "name" {
  value = aws_scheduler_schedule_group.this.name
}

output "arn" {
  value = aws_scheduler_schedule_group.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
