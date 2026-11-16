output "bucket" {
  value = module.bucket.name
}

output "function_name" {
  value = module.function.function_name
}

output "schedule_expression" {
  value = aws_scheduler_schedule.this.schedule_expression
}
