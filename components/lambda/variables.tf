variable "function_name" {
  description = "Function name; also names its log group, role (<name>-role) and policy (<name>-policy)."
  type        = string
}

variable "package_type" {
  description = "Zip (filename, handler, runtime, layers) or Image (image_uri; the image carries everything else)."
  type        = string
  default     = "Zip"

  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "package_type must be Zip or Image."
  }
}

variable "image_uri" {
  description = "package_type = Image: the ECR image, <repository url>:<tag>, built for architecture."
  type        = string
  default     = null
}

variable "handler" {
  description = "package_type = Zip: module.function, e.g. lambda_function.lambda_handler."
  type        = string
  default     = null
}

variable "runtime" {
  description = "package_type = Zip: e.g. python3.12."
  type        = string
  default     = null
}

variable "architecture" {
  description = "Instruction set: x86_64 or arm64 (Graviton, about 20% cheaper per GB-second)."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "filename" {
  description = "package_type = Zip: the deployment zip."
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "package_type = Zip: base64 SHA-256 of the zip; a change redeploys the code."
  type        = string
  default     = null
}

variable "timeout" {
  type = number
}

variable "memory_size" {
  type = number
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions; -1 = unreserved."
  type        = number
}

variable "environment" {
  description = "Environment variables."
  type        = map(string)
  sensitive   = true
}

variable "policy_statements" {
  description = "IAM statements added to the role besides writing its own log group."
  type        = any
}

variable "url_auth" {
  description = "Function URL authorization: NONE (public URL, the function checks callers) or AWS_IAM (SigV4)."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.url_auth)
    error_message = "url_auth must be NONE or AWS_IAM."
  }
}

variable "layers" {
  description = "Layer version ARNs (dependencies the zip does not carry); package_type = Image: none."
  type        = list(string)
  default     = []
}

variable "ephemeral_storage_mb" {
  description = "/tmp size in MB, 512 to 10240."
  type        = number
  default     = 512

  validation {
    condition     = var.ephemeral_storage_mb >= 512 && var.ephemeral_storage_mb <= 10240
    error_message = "ephemeral_storage_mb: 512 to 10240."
  }
}

variable "vpc_subnet_ids" {
  description = "Private subnets to run in; [] = no VPC (the default: S3 and the internet directly)."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security groups when vpc_subnet_ids is set."
  type        = list(string)
  default     = []
}

variable "function_url" {
  description = "Give the function a Function URL. false = invoked only by other AWS services (Step Functions, S3, ...)."
  type        = bool
  default     = true
}

variable "role_name" {
  description = "IAM role name; null = <function_name>-role."
  type        = string
  default     = null
}

variable "policy_name" {
  description = "The role's inline policy name; null = <function_name>-policy."
  type        = string
  default     = null
}

variable "policy_arns" {
  description = "Managed policies attached to the role as they are."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Days the function's CloudWatch logs are kept."
  type        = number
  default     = 14
}
