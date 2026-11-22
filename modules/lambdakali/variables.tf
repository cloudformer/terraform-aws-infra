variable "project_name" {
  description = "Names everything: function <project_name>-lambda, CodeBuild project <project_name>-scanner, the ECR repository <project_name>, the bucket <project_name>-reports-<account id>, the secrets /<project_name>/secrets/<name>. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "scanner_policy_statements" {
  description = "Extra IAM statements added to every scanner's role, so a command can reach what it needs — e.g. read a vault path: [{ Effect = \"Allow\", Action = [\"s3:GetObject\"], Resource = \"arn:aws:s3:::my-vaults/*\" }]. [] = the scanner can only run and write its reports."
  type        = any
  default     = []
}

# Sign-in: two methods, each on or off; a request passes when any method that is on accepts it (at least one must be on).
variable "http_auth" {
  description = "Sign-in with a user and password (HTTP Basic); the page asks for them. enabled = false: the other fields are ignored."
  type = object({
    enabled  = bool
    username = optional(string, "")
    password = optional(string, "") # at least 16 characters: the web UI is a public URL
  })
  default   = { enabled = false }
  sensitive = true

  validation {
    condition     = !var.http_auth.enabled || (length(var.http_auth.username) > 0 && length(var.http_auth.password) >= 16)
    error_message = "http_auth: enabled needs a username and a password of at least 16 characters (the web UI is a public URL)."
  }
}

variable "cloudflare_auth" {
  description = "Sign-in through Cloudflare Access in front of the Function URL: the Lambda checks the JWT Cloudflare adds (team's public keys, aud, issuer, expiry). With http_auth off, the URL opened directly serves nothing, the page included. enabled = false: the other fields are ignored."
  type = object({
    enabled = bool
    team    = optional(string, "") # <team>.cloudflareaccess.com
    aud     = optional(string, "") # the Access application's AUD tag
  })
  default = { enabled = false }

  validation {
    condition     = !var.cloudflare_auth.enabled || (can(regex("^[a-z0-9-]+$", var.cloudflare_auth.team)) && length(var.cloudflare_auth.aud) > 0)
    error_message = "cloudflare_auth: enabled needs team (the <team> in <team>.cloudflareaccess.com: lowercase letters, digits, '-') and aud (the Access application's AUD tag)."
  }

  validation {
    condition     = var.cloudflare_auth.enabled || nonsensitive(var.http_auth.enabled)
    error_message = "Turn on http_auth or cloudflare_auth (or both): a command console is never deployed open."
  }
}

variable "lambdakali_version" {
  description = "lambdakali release deployed from PyPI (lambdakali==<version>): the Lambda and the scan images are built from it. The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.lambdakali_version))
    error_message = "lambdakali_version: X.Y.Z, e.g. 0.1.1."
  }
}

variable "secrets" {
  description = "Names of the secrets a command may use, e.g. [\"API_TOKEN\"]: each is an SSM SecureString /<project_name>/secrets/<name>, created holding CHANGE-ME, and reaches every command as the environment variable <name>, masked as *** in the output. Set the value with: aws ssm put-parameter --name /<project_name>/secrets/<name> --type SecureString --overwrite --value '...'"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.secrets : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", s))])
    error_message = "secrets: environment variable names, letters, digits and '_', not starting with a digit."
  }
}

variable "image_variants" {
  description = "Which Kali image tiers to build and offer in the console: slim (common tools, small), common (~80% of tools, 2-3 GB), full (everything, 5-8 GB). Each is built once at apply (Docker, arm64). More tiers = longer apply and more ECR storage."
  type        = list(string)
  default     = ["slim", "common"]

  validation {
    condition     = length(var.image_variants) > 0 && alltrue([for v in var.image_variants : contains(["slim", "common", "full"], v)])
    error_message = "image_variants: a non-empty subset of [\"slim\", \"common\", \"full\"]."
  }
}

variable "default_image" {
  description = "The image tier the console offers first; must be one of image_variants."
  type        = string
  default     = "common"

  validation {
    condition     = contains(var.image_variants, var.default_image)
    error_message = "default_image must be one of image_variants."
  }
}

variable "compute_type" {
  description = "The instance size Start offers first: BUILD_GENERAL1_SMALL (2 vCPU, 3 GB), BUILD_GENERAL1_MEDIUM (4 vCPU, 7 GB) or BUILD_GENERAL1_LARGE (8 vCPU, 15 GB). Billed per minute while a scanner is on."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE"], var.compute_type)
    error_message = "compute_type must be BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM or BUILD_GENERAL1_LARGE."
  }
}

variable "max_scanners" {
  description = "Scanners that may be on at the same time (1 to 10); Start in the UI is refused beyond it. Each runs one command at a time."
  type        = number
  default     = 2

  validation {
    condition     = var.max_scanners >= 1 && var.max_scanners <= 10
    error_message = "max_scanners: 1 to 10."
  }
}

variable "idle_shutdown_minutes" {
  description = "A scanner shuts down by itself after this many minutes without a task (1 to max_session_minutes); Shut down in the UI stops it at once."
  type        = number
  default     = 10

  validation {
    condition     = var.idle_shutdown_minutes >= 1 && var.idle_shutdown_minutes <= var.max_session_minutes
    error_message = "idle_shutdown_minutes: 1 to max_session_minutes."
  }
}

variable "max_session_minutes" {
  description = "A scanner is stopped this many minutes after it was started, busy or not (5 to 2160): the bound on what one forgotten scanner costs, and the most its lease (chosen at Start, +1h from the UI) can reach."
  type        = number
  default     = 480

  validation {
    condition     = var.max_session_minutes >= 5 && var.max_session_minutes <= 2160
    error_message = "max_session_minutes: 5 to 2160 (CodeBuild's limit, 36 hours)."
  }
}

variable "report_retention_days" {
  description = "Days the output files (and the tasks, claims and leases) are kept in the bucket."
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Days the scanners' logs (CloudWatch) are kept."
  type        = number
  default     = 14
}

variable "function_url_auth" {
  description = "How the Function URL is protected. NONE = public URL, the Lambda checks http_auth / cloudflare_auth. AWS_IAM = AWS checks a SigV4 signature + IAM permission first; the browser UI cannot sign requests, so it is unusable in this mode."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "architecture" {
  description = "Instruction set of the Lambda and the scan instances: arm64 (Graviton, cheaper) or x86_64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the bucket with everything in it. false = destroy stops at a non-empty bucket."
  type        = bool
  default     = true
}

variable "build_image" {
  description = "Build the scan images with Docker on the machine running Terraform and push them to the ECR repository. false = pushed some other way (CI); the mock tests use false (no Docker, no ECR login)."
  type        = bool
  default     = true
}
