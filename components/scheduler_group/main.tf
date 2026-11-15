# One EventBridge Scheduler group (free until a schedule fires) and the IAM role its schedules run as; the
# schedules themselves are created by the application, inside this group.

data "aws_caller_identity" "me" {}

resource "aws_scheduler_schedule_group" "this" {
  name = var.name
}

resource "aws_iam_role" "this" {
  name = coalesce(var.role_name, "${var.name}-scheduler")
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.me.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name = coalesce(var.role_name, "${var.name}-scheduler")
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}
