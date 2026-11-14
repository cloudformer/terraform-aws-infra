variable "name" {
  description = "Bucket name (global across AWS)."
  type        = string
}

variable "force_destroy" {
  description = "true = destroy deletes the bucket with every object in it. false = destroy stops at a non-empty bucket."
  type        = bool
}

variable "versioning" {
  description = "true = keep every overwritten or deleted object as a noncurrent version (expire them with a lifecycle rule)."
  type        = bool
  default     = false
}
