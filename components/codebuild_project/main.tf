# One CodeBuild project with everything that belongs to it alone: its log group, its IAM role and policy.
# No source, no artifacts: each build runs the image's own command (buildspec) on a fresh instance, and the
# caller starts builds (StartBuild) with per-build environment variables.

locals {
  # CodeBuild's environment type per instruction set
  type = { arm64 = "ARM_CONTAINER", x86_64 = "LINUX_CONTAINER" }
}

# ---------------- logs: one group per project; the role may write only here ----------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/codebuild/${var.name}"
  retention_in_days = var.log_retention_days
}

# ---------------- IAM: its own role; pulls its image, writes its logs; the caller names what else ----------------
resource "aws_iam_role" "this" {
  name = "${var.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "this" {
  name = "${var.name}-policy"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      },
      {
        # the login token is account-wide: no resource scope exists for it
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = var.ecr_repository_arn
      }
    ], var.policy_statements)
  })
}

# ---------------- the project ----------------
resource "aws_codebuild_project" "this" {
  name                   = var.name
  service_role           = aws_iam_role.this.arn
  build_timeout          = var.timeout_minutes
  concurrent_build_limit = var.concurrent_build_limit

  source {
    type      = "NO_SOURCE"
    buildspec = var.buildspec
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type                        = local.type[var.architecture]
    compute_type                = var.compute_type
    image                       = var.image
    image_pull_credentials_type = "SERVICE_ROLE" # a private ECR image, pulled with the role above

    dynamic "environment_variable" {
      for_each = var.environment
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.this.name
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  # the role must be able to pull the image before CodeBuild accepts the project
  depends_on = [aws_iam_role_policy.this]
}
