variable "name" {
  type = string
}

variable "retention_seconds" {
  description = "How long a message is kept, 60 to 1209600 (14 days, the maximum)."
  type        = number
  default     = 1209600
}
