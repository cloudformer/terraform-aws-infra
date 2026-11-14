variable "function_name" {
  description = "Function name; also names its log group, role (<name>-role) and policy (<name>-policy)."
  type        = string
}

variable "handler" {
  type = string
}

variable "runtime" {
  type = string
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
  description = "The deployment zip."
  type        = string
}

variable "source_code_hash" {
  description = "base64 SHA-256 of the zip; a change redeploys the code."
  type        = string
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

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.url_auth)
    error_message = "url_auth must be NONE or AWS_IAM."
  }
}
