variable "project_name" {
  description = "Names everything: function <project_name>-lambda, its role <project_name>-lambda-role, the bucket <project_name>-vaults-<account id> unless bucket is set. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "console_auth_username" {
  description = "Web UI sign-in user (HTTP Basic), also the owner name in access records. Each vault still needs its own master password."
  type        = string
}

variable "console_auth_password" {
  description = "Web UI sign-in password (HTTP Basic). At least 16 characters."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.console_auth_password) >= 16
    error_message = "console_auth_password must be at least 16 characters (the web UI is a public URL)."
  }
}

variable "s3keepass_version" {
  description = "s3keepass release deployed from PyPI (s3keepass==<version>). The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.s3keepass_version))
    error_message = "s3keepass_version: X.Y.Z, e.g. 0.1.1."
  }
}

variable "bucket" {
  description = "Bucket name (global across AWS). null = <project_name>-vaults-<account id>."
  type        = string
  default     = null
}

variable "console" {
  description = "Serve the web UI at GET / on the Function URL. false = API only."
  type        = bool
  default     = true
}

variable "function_url_auth" {
  description = "How the Function URL is protected. NONE = public URL, user/password (HTTP Basic) is checked. AWS_IAM = AWS checks a SigV4 signature + IAM permission first; the browser UI cannot sign requests, so it is unusable in this mode."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "keep_versions" {
  description = "Older versions kept per vault file (each save is one S3 version; Versions in the UI restores one). Older ones go a day after they are replaced."
  type        = number
  default     = 5

  validation {
    condition     = var.keep_versions >= 1 && var.keep_versions <= 100
    error_message = "keep_versions: 1 to 100 (an S3 lifecycle rule keeps at most 100 noncurrent versions)."
  }
}

variable "log_retention_days" {
  description = "Days the access records (log/: every read, save, unlock …) are kept."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH every vault and version in it. false = destroy stops at a non-empty bucket and the vaults survive."
  type        = bool
  default     = false
}

variable "architecture" {
  description = "Lambda instruction set: arm64 (Graviton, cheaper) or x86_64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "custom_template" {
  description = "Advanced settings: overrides of the new-vault template shipped in the package (base_template.json: Argon2id 128 MiB, 2 lanes, tuned to >= 2000 ms per unlock; AES-256; no groups or extra fields; no entry history; no recycle bin). Only the fields set here change; kdf is merged field by field. Applies to vaults created from then on."
  type = object({
    kdf = optional(object({
      memory_mib  = optional(number) # Argon2id memory per unlock attempt
      parallelism = optional(number) # Argon2id lanes
      unlock_ms   = optional(number) # passes are tuned on the creating device until one unlock takes at least this long
    }))
    cipher            = optional(string)       # "aes256"
    groups            = optional(list(string)) # groups a new vault starts with
    fields            = optional(list(string)) # extra (protected) fields every new entry offers
    history_max_items = optional(number)       # entry history kept inside the vault file (0 = none)
    recycle_bin       = optional(bool)         # false = a delete is final
  })
  default = null

  validation {
    condition     = try(var.custom_template.kdf.memory_mib, null) == null || try(var.custom_template.kdf.memory_mib >= 16 && var.custom_template.kdf.memory_mib <= 1024, false)
    error_message = "custom_template.kdf.memory_mib: 16 to 1024 (a phone browser may fail above 256)."
  }

  validation {
    condition     = try(var.custom_template.cipher, null) == null || try(var.custom_template.cipher == "aes256", false)
    error_message = "custom_template.cipher: \"aes256\"."
  }
}
