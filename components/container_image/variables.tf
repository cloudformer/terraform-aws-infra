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

variable "build_args" {
  description = "Docker build args passed to every architecture, e.g. { KALI_TIER = \"common\" }. {} = none."
  type        = map(string)
  default     = {}
}

variable "architectures" {
  description = "Instruction sets to build and push (tags <tag>-arm64 / <tag>-x86_64). Fewer = faster, less ECR storage."
  type        = list(string)
  default     = ["arm64", "x86_64"]

  validation {
    condition     = length(var.architectures) > 0 && alltrue([for a in var.architectures : contains(["arm64", "x86_64"], a)])
    error_message = "architectures: a non-empty subset of [\"arm64\", \"x86_64\"]."
  }
}
