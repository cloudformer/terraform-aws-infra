variable "name" {
  type = string
}

variable "hash_key" {
  description = "Partition key (string)."
  type        = string
  default     = "pk"
}

variable "range_key" {
  description = "Sort key (string); null = none."
  type        = string
  default     = "sk"
}
