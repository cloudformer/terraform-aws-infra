variable "name" {
  description = "Project name; also names its log group (/aws/codebuild/<name>), role (<name>-role) and policy (<name>-policy)."
  type        = string
}

variable "image" {
  description = "The build image in ECR, <repository url>:<tag>, built for architecture."
  type        = string
}

variable "ecr_repository_arn" {
  description = "The ECR repository holding image: the role may pull from it."
  type        = string
}

variable "architecture" {
  description = "Instruction set: arm64 (Graviton, cheaper per minute) or x86_64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "compute_type" {
  description = "Instance size: BUILD_GENERAL1_SMALL (2 vCPU, 3 GB), BUILD_GENERAL1_MEDIUM (4 vCPU, 7 GB) or BUILD_GENERAL1_LARGE (8 vCPU, 15 GB)."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.compute_type)
    error_message = "compute_type must be BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM or BUILD_GENERAL1_LARGE."
  }
}

variable "timeout_minutes" {
  description = "A build still running after this many minutes is stopped (5 to 2160)."
  type        = number
  default     = 60

  validation {
    condition     = var.timeout_minutes >= 5 && var.timeout_minutes <= 2160
    error_message = "timeout_minutes: 5 to 2160 (CodeBuild's limit, 36 hours)."
  }
}

variable "concurrent_build_limit" {
  description = "Builds running at the same time; one more is refused by StartBuild."
  type        = number
  default     = 1

  validation {
    condition     = var.concurrent_build_limit >= 1
    error_message = "concurrent_build_limit: at least 1."
  }
}

variable "buildspec" {
  description = "The buildspec (YAML) every build runs."
  type        = string
}

variable "environment" {
  description = "Environment variables of every build (plain text: no secrets). StartBuild may add or override some per build."
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = "IAM statements added to the role besides writing its own log group and pulling its image."
  type        = any
  default     = []
}

variable "log_retention_days" {
  description = "Days the builds' CloudWatch logs are kept."
  type        = number
  default     = 14
}
