terraform {
  required_version = ">= 1.9" # a validation that reads another variable
  required_providers {
    aws      = { source = "hashicorp/aws", version = "~> 6.0" }
    archive  = { source = "hashicorp/archive", version = "~> 2.4" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}
