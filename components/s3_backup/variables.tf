variable "name" {
  description = "Names the copier <name>-lambda (role <name>-lambda-role), the scheduler group and schedule <name>, its role <name>-scheduler."
  type        = string
}

variable "source_bucket" {
  description = "The bucket backed up; the backup bucket is <source_bucket>-backup."
  type        = string
}

variable "source_bucket_arn" {
  type = string
}

variable "prefixes" {
  description = "Only objects under these prefixes are copied; [\"\"] = the whole bucket."
  type        = list(string)
}

variable "every" {
  description = "How often a snapshot is taken: <n>h or <n>d, e.g. 1h, 6h, 1d, 7d."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*[hd]$", var.every))
    error_message = "every: <n>h or <n>d, e.g. 6h or 1d."
  }
}

variable "keep_days" {
  description = "Days a snapshot is kept before the lifecycle rule deletes it."
  type        = number

  validation {
    condition     = var.keep_days >= 1
    error_message = "keep_days: at least 1."
  }
}

variable "force_destroy" {
  description = "true = destroy deletes the backup bucket with every snapshot. false = destroy stops at a non-empty backup bucket."
  type        = bool
}
