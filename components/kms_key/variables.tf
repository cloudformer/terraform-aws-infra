variable "alias" {
  description = "The key's alias, without the alias/ prefix."
  type        = string
}

variable "description" {
  type = string
}

variable "deletion_window_in_days" {
  description = "Days between destroy and the key's deletion (7 to 30)."
  type        = number
  default     = 7
}
