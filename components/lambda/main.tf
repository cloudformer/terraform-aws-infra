# One Lambda function with everything that belongs to it alone: its log group, its IAM role and policy,
# and a Function URL.

# ---------------- logs: one group per function, kept 14 days; the role may write only here ----------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

# ---------------- IAM: its own role; the caller names what else it may do ----------------
resource "aws_iam_role" "this" {
  name = "${var.function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name = "${var.function_name}-policy"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.this.arn}:*"
    }], var.policy_statements)
  })
}

# ---------------- the function ----------------
resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = aws_iam_role.this.arn
  runtime          = var.runtime
  handler          = var.handler
  filename         = var.filename
  source_code_hash = var.source_code_hash
  timeout          = var.timeout
  memory_size      = var.memory_size

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}

# ---------------- Function URL ----------------
# No CORS: a console is served by the same URL (same origin) and API clients are not browsers.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = var.url_auth
}

# url_auth = NONE: a public URL. AWS requires a resource policy that lets anyone invoke it, so the two
# statements below say principal = "*" — that is what "public URL" means; the function itself must check
# who is calling. Since Oct 2025 AWS requires BOTH statements:
#   lambda:InvokeFunctionUrl  with FunctionUrlAuthType = NONE
#   lambda:InvokeFunction     with InvokedViaFunctionUrl = true (only through the URL, not a direct Invoke)
# url_auth = AWS_IAM: AWS verifies SigV4 + IAM first; neither statement is created.
resource "aws_lambda_permission" "url" {
  count                  = var.url_auth == "NONE" ? 1 : 0
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  principal              = "*"
  function_url_auth_type = "NONE"

  # one change to a function at a time: Lambda answers 409 "concurrent update operation" otherwise
  depends_on = [aws_lambda_function_url.this]
}

resource "aws_lambda_permission" "url_invoke" {
  count                    = var.url_auth == "NONE" ? 1 : 0
  statement_id             = "AllowPublicFunctionUrlInvoke"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.this.function_name
  principal                = "*"
  invoked_via_function_url = true

  depends_on = [aws_lambda_permission.url]
}
