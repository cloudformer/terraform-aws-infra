variable "project_name" {
  description = "Names everything: <project_name>-console, -worker, -run (state machine), -deps (layer), -schedule-dlq, the table and the scheduler group <project_name>, the bucket <project_name>-data-<account id> unless bucket is set. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "console_auth_username" {
  description = "Sign-in user (HTTP Basic) for the console and every API client (lambdaflow.client)."
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

variable "lambdaflow_version" {
  description = "lambdaflow release deployed from PyPI (lambdaflow==<version>). The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.lambdaflow_version))
    error_message = "lambdaflow_version: X.Y.Z, e.g. 0.1.1."
  }
}

variable "bucket" {
  description = "Bucket name (global across AWS). null = <project_name>-data-<account id>."
  type        = string
  default     = null
}

variable "console" {
  description = "Serve the web console at GET / on the Function URL. false = API only."
  type        = bool
  default     = true
}

variable "function_url_auth" {
  description = "How the Function URL is protected. NONE = public URL, the console checks the user / password. AWS_IAM = AWS checks a SigV4 signature + IAM permission first; the browser console cannot sign requests, so it is unusable in this mode."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "task_policy_arns" {
  description = "IAM policies your tasks need (S3 buckets they read, APIs they call), attached to the worker role. Granted here and only here: the console can never widen what task code may do."
  type        = list(string)
  default     = []
}

variable "task_env" {
  description = "Environment variables for task code (AIRFLOW_VAR_* / AIRFLOW_CONN_* work as in Airflow)."
  type        = map(string)
  default     = {}
}

variable "task_timeout" {
  description = "Seconds one task may run (the worker Lambda's timeout, at most 900); a task that needs longer belongs on Airflow / MWAA."
  type        = number
  default     = 900

  validation {
    condition     = var.task_timeout >= 10 && var.task_timeout <= 900
    error_message = "task_timeout must be between 10 and 900 seconds (the Lambda limit)."
  }
}

variable "worker_memory" {
  description = "MB for the worker Lambda (CPU grows with it)."
  type        = number
  default     = 1024
}

variable "max_parallel_tasks" {
  description = "Tasks of one DAG run that run at the same time (the state machine's Map concurrency)."
  type        = number
  default     = 10
}

variable "paused_at_creation" {
  description = "New DAGs start paused, as in Airflow."
  type        = bool
  default     = true
}

variable "task_log_days" {
  description = "Days task logs are kept in S3 (logs/)."
  type        = number
  default     = 30
}

variable "cloudwatch_log_days" {
  description = "Days the Lambdas' CloudWatch logs are kept."
  type        = number
  default     = 14
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket WITH the DAG files and task logs (keep your DAGs in git). false = destroy stops at a non-empty bucket."
  type        = bool
  default     = false
}
