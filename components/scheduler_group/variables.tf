variable "name" {
  type = string
}

variable "policy_statements" {
  description = "IAM statements for the role the schedules run as (what a schedule may start)."
  type        = any
}

variable "role_name" {
  description = "IAM role name, also its inline policy's; null = <name>-scheduler."
  type        = string
  default     = null
}
