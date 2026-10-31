variable "project_name" {
  description = "Names everything: bucket <project_name>-db-<account id>, functions <project_name>-db-lambda and <project_name>-db-ro-lambda, their roles <function>-role. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "console_auth_username" {
  description = "Database user (HTTP Basic): console login AND the user= clients connect() with, like the RDS master username; still required with console = false."
  type        = string
}

variable "console_auth_password" {
  description = "Database password (HTTP Basic): console login AND the password= clients connect() with. At least 16 characters."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.console_auth_password) >= 16
    error_message = "console_auth_password must be at least 16 characters (the endpoint is a public URL)."
  }
}

variable "s3rds_version" {
  description = "s3rds release deployed from PyPI (s3rds[server]==<version>). The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.3.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.s3rds_version))
    error_message = "s3rds_version: X.Y.Z, e.g. 0.3.4."
  }
}

variable "console" {
  description = "Serve the built-in web console at GET / on the endpoints. false = API only."
  type        = bool
  default     = true
}

variable "function_url_auth" {
  description = "How the endpoints are protected. NONE = public URL, user/password (HTTP Basic) is checked. AWS_IAM = AWS checks a SigV4 signature + IAM permission first, then user/password; the browser console cannot sign requests, so it is unusable in this mode."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "db_ro" {
  description = "Also deploy the read-only endpoint (<project_name>-db-ro-lambda): its own role, GetObject only, unlimited concurrency. false = the read/write endpoint only."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH every database in it. false = destroy stops at a non-empty bucket and the data survives."
  type        = bool
  default     = true
}
