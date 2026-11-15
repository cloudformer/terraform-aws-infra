variable "name" {
  type = string
}

variable "definition" {
  description = "The state machine as an object (Amazon States Language); encoded to JSON here."
  type        = any
}

variable "policy_statements" {
  description = "IAM statements for the state machine's role."
  type        = any
}

variable "role_name" {
  description = "IAM role name, also its inline policy's; null = <name>-role."
  type        = string
  default     = null
}
