variable "project_name" {
  description = "Names everything: functions <project_name>-lambda (web), <project_name>-manage, <project_name>-db-lambda (s3rds), their roles <function>-role, the bucket <project_name>-db-<account id> unless bucket is set. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "console_auth_username" {
  description = "s3rds' sign-in user (HTTP Basic): Healthchecks connects to its database with it, and you sign in to db_url's console with it. It guards every database client, even with console = false."
  type        = string
}

variable "console_auth_password" {
  description = "s3rds' sign-in password (HTTP Basic), at least 16 characters: the database's Function URL is public."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.console_auth_password) >= 16
    error_message = "console_auth_password must be at least 16 characters (the Function URL is public)."
  }
}

variable "secret_key" {
  description = "Django's SECRET_KEY (sessions, CSRF, signed links), at least 16 characters; keep it stable. It is also the setup key: until the first account exists, the setup page asks for it."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.secret_key) >= 16
    error_message = "secret_key must be at least 16 characters (it guards the setup page of a fresh deployment)."
  }
}

variable "lambdachecks_version" {
  description = "lambdachecks release deployed from PyPI (lambdachecks==<version>). The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.lambdachecks_version))
    error_message = "lambdachecks_version: X.Y.Z, e.g. 0.1.0."
  }
}

variable "bucket" {
  description = "The database bucket's name (global across AWS). null = <project_name>-db-<account id>."
  type        = string
  default     = null
}

variable "console" {
  description = "Serve s3rds' web console at GET / on db_url (Healthchecks' tables and rows). false = API only."
  type        = bool
  default     = true
}

variable "registration_open" {
  description = "Let anyone sign up from the login page (Healthchecks' REGISTRATION_OPEN). false = accounts via the setup page / createsuperuser only."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Healthchecks' database in s3rds (db/<db_name>.sqlite); the manage function creates it if missing."
  type        = string
  default     = "healthchecks"
}

variable "architecture" {
  description = "Instruction set of the three Lambdas: arm64 (Graviton, about 20% cheaper) or x86_64. Both are built, so switching needs no rebuild."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "memory_size" {
  description = "MB for the web and the manage function; more memory = more CPU = faster Django cold starts and password hashing."
  type        = number
  default     = 1024
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH Healthchecks' database. false = destroy stops at a non-empty bucket and the data survives."
  type        = bool
  default     = false
}
