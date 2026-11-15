# One Step Functions state machine (STANDARD: billed per state transition, ≈ $0 idle) with its own IAM role;
# the caller names what the role may do (e.g. invoke its Lambdas).

data "aws_caller_identity" "me" {}

resource "aws_iam_role" "this" {
  name = coalesce(var.role_name, "${var.name}-role")
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.me.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name = coalesce(var.role_name, "${var.name}-role")
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = aws_iam_role.this.arn
  type       = "STANDARD"
  definition = jsonencode(var.definition)
}
