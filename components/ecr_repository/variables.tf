variable "name" {
  description = "Repository name."
  type        = string
}

variable "keep_images" {
  description = "Images kept; older ones expire (count every tag: one per architecture per build)."
  type        = number
  default     = 10
}
