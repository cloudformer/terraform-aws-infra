terraform {
  required_version = ">= 1.10" # ephemeral: the ECR login token never reaches the state
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
