variable "name" {
  description = "Layer name; each publish is a new version of it."
  type        = string
}

variable "source_dir" {
  description = "The staged directory: python/<packages> inside."
  type        = string
}

variable "compatible_runtimes" {
  type    = list(string)
  default = ["python3.12"]
}

variable "compatible_architectures" {
  description = "x86_64 and / or arm64: what the packages inside were built for."
  type        = list(string)
  default     = ["x86_64"]
}
