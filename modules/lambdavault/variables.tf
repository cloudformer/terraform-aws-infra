variable "project_name" {
  description = "Names everything: functions <project_name>-lambda (Vault) and <project_name>-proxy-lambda (the URL), their roles <project_name>-lambda-role / <project_name>-proxy-role, the ECR repository <project_name>, the bucket <project_name>-data-<account id> unless bucket is set, the KMS alias alias/<project_name>-seal (seal = kms) or the SSM parameter /<project_name>/unseal-key (seal = ssm). Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "lambdavault_version" {
  description = "lambdavault release deployed from PyPI (lambdavault==<version>): the Vault image and the proxy are built from it. The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.lambdavault_version))
    error_message = "lambdavault_version: X.Y.Z, e.g. 0.1.2."
  }
}

variable "seal" {
  description = "How Vault is unsealed at a cold start. type = ssm (free): Shamir seal with one key, kept as an SSM SecureString /<project_name>/unseal-key (AWS's aws/ssm key, standard tier), written at `vault operator init -key-shares=1 -key-threshold=1`. type = kms (≈ $1 a month): a KMS key, Vault's awskms auto-unseal (`vault operator init -recovery-shares=1 -recovery-threshold=1`); kms_deletion_window_days = how long a destroyed key can still be recovered. Do not change type on an initialized vault: that needs a seal migration."
  type = object({
    type                     = string
    kms_deletion_window_days = optional(number, 7) # type = kms only: 7 to 30
  })
  default = { type = "ssm" }

  validation {
    condition     = contains(["ssm", "kms"], var.seal.type)
    error_message = "seal.type must be ssm or kms."
  }

  validation {
    condition     = var.seal.kms_deletion_window_days >= 7 && var.seal.kms_deletion_window_days <= 30
    error_message = "seal.kms_deletion_window_days: 7 to 30."
  }
}

variable "bucket" {
  description = "Bucket name (global across AWS). null = <project_name>-data-<account id>."
  type        = string
  default     = null
}

variable "architecture" {
  description = "The architecture the Vault and proxy functions run: arm64 (Graviton, ~20% cheaper) or x86_64. Both images are always built, so switching needs no rebuild."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "memory_size" {
  description = "The Vault function's memory in MB (CPU scales with it; Vault starts faster with more)."
  type        = number
  default     = 1024
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH all of Vault's data. false = destroy stops at a non-empty bucket and the data survives. Keep false for real secrets."
  type        = bool
  default     = false
}

variable "build_image" {
  description = "Build the Vault image with Docker on the machine running Terraform and push it to the ECR repository. false = it is pushed some other way (CI); the mock tests use false (no Docker, no ECR login)."
  type        = bool
  default     = true
}
