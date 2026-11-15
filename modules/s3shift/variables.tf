variable "project_name" {
  description = "Names everything: function <project_name>-lambda, its role <project_name>-lambda-role, the layer <project_name>-deps, the bucket <project_name>-data-<account id> unless bucket is set. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "console_auth_username" {
  description = "Sign-in user (HTTP Basic) for the console and every client (redshift_connector user=)."
  type        = string
}

variable "console_auth_password" {
  description = "Sign-in password (HTTP Basic), at least 16 characters: the Function URL is public."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.console_auth_password) >= 16
    error_message = "console_auth_password must be at least 16 characters (the Function URL is public)."
  }
}

variable "s3shift_version" {
  description = "s3shift release deployed from PyPI (s3shift==<version>). The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.s3shift_version))
    error_message = "s3shift_version: X.Y.Z, e.g. 0.1.2."
  }
}

variable "bucket" {
  description = "Bucket name (global across AWS). null = <project_name>-data-<account id>."
  type        = string
  default     = null
}

variable "console" {
  description = "Serve the query editor at GET / on the Function URL. false = API only."
  type        = bool
  default     = true
}

variable "function_url_auth" {
  description = "How the Function URL is protected. NONE = public URL, the Lambda checks the user / password. AWS_IAM = AWS checks a SigV4 signature + IAM permission first; the browser console cannot sign requests, so it is unusable in this mode."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "memory_mb" {
  description = "Lambda memory: also its CPU share and the largest query DuckDB can hold (128 to 10240)."
  type        = number
  default     = 3008
}

variable "read_buckets" {
  description = "Your data buckets s3shift may read (external tables, COPY sources), e.g. [\"my-data-lake\"]."
  type        = list(string)
  default     = []
}

variable "vpc_subnet_ids" {
  description = "Private subnets, only for CREATE EXTERNAL SCHEMA against a private RDS. The Lambda then needs an S3 gateway endpoint (or NAT) to reach S3."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security groups for the VPC config (allowed by the RDS security group on 3306 / 5432)."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH the catalog and managed tables. false = destroy stops at a non-empty bucket and the data survives."
  type        = bool
  default     = false
}
