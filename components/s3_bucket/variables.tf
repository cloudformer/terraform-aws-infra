variable "name" {
  description = "Bucket name (global across AWS)."
  type        = string
}

variable "force_destroy" {
  description = "true = destroy deletes the bucket with every object in it. false = destroy stops at a non-empty bucket."
  type        = bool
}
