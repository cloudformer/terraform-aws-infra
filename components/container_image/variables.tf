variable "repository_url" {
  description = "The ECR repository: <account>.dkr.ecr.<region>.amazonaws.com/<name>."
  type        = string
}

variable "tag" {
  description = "The image tag (without the -arm64 / -x86_64 suffix); a new tag rebuilds and pushes."
  type        = string
}

variable "context" {
  description = "The local directory holding the Dockerfile and what it copies."
  type        = string
}

variable "build" {
  description = "Build and push here with Docker. false = the image is expected in the repository already (pushed by CI, or a mock test)."
  type        = bool
  default     = true
}
