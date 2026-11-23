variable "project_name" {
  description = "Names everything: the Lambda <project_name>-lambda, the launch template, the lease bucket <project_name>-<account id>, and the Project tag every jump carries. Unique per AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.project_name))
    error_message = "project_name: 2-40 characters, lowercase letters, digits and '-' (it becomes part of an S3 bucket name)."
  }
}

variable "networks" {
  description = <<-EOT
    The network profiles a jump can be launched into — the console's Network dropdown. Each is a subnet + security
    group(s) (and whether to give it a public IP). Admins define these in IaC; the web page can only pick one.
      { database = { subnets = ["subnet-…"], security_group_ids = ["sg-…"] }
        internet = { subnets = ["subnet-public-…"], security_group_ids = ["sg-…"], public = true } }
    Each profile's security group decides exactly which hosts/ports the jump can reach.
  EOT
  type = map(object({
    subnets            = list(string)
    security_group_ids = list(string)
    public             = optional(bool, false)
  }))

  validation {
    condition     = length(var.networks) > 0 && alltrue([for n in var.networks : length(n.subnets) > 0 && length(n.security_group_ids) > 0])
    error_message = "networks: at least one profile, each with a non-empty subnets and security_group_ids."
  }
}

variable "default_network" {
  description = "The network profile the console offers first; must be a key of networks. Empty = the first one."
  type        = string
  default     = ""

  validation {
    condition     = var.default_network == "" || contains(keys(var.networks), var.default_network)
    error_message = "default_network must be one of the networks keys."
  }
}

variable "targets" {
  description = "The map-mode target dropdown: private endpoints you forward to your laptop, as host:port, e.g. [\"db-primary.xxx:3306\", \"cache-01.xxx:6379\"]. Only hosts a jump's security group allows will actually connect; a custom host:port can also be typed."
  type        = list(string)
  default     = []
}

# Sign-in: two methods, each on or off; a request passes when any method that is on accepts it (at least one must be on).
variable "http_auth" {
  description = "Sign-in with a user and password (HTTP Basic). enabled = false: the other fields are ignored."
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
  description = "Sign-in through Cloudflare Access in front of the Function URL. enabled = false: the other fields are ignored."
  type = object({
    enabled = bool
    team    = optional(string, "")
    aud     = optional(string, "")
  })
  default = { enabled = false }

  validation {
    condition     = !var.cloudflare_auth.enabled || (can(regex("^[a-z0-9-]+$", var.cloudflare_auth.team)) && length(var.cloudflare_auth.aud) > 0)
    error_message = "cloudflare_auth: enabled needs team and aud (the Access application's AUD tag)."
  }

  validation {
    condition     = var.cloudflare_auth.enabled || nonsensitive(var.http_auth.enabled)
    error_message = "Turn on http_auth or cloudflare_auth (or both): a jump console is never deployed open."
  }
}

variable "ztna_version" {
  description = "ztna release deployed from PyPI (ztna==<version>): the Lambda is built from it. The default is the version this module was tested with; set another to upgrade without a new module version."
  type        = string
  default     = "0.1.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.ztna_version))
    error_message = "ztna_version: X.Y.Z, e.g. 0.1.0."
  }
}

variable "instance_type" {
  description = "The EC2 type for a jump (it only tunnels, so micro is plenty). arm64 by default (cheaper); match the AMI architecture."
  type        = string
  default     = "t4g.micro"
}

variable "architecture" {
  description = "The jump AMI / Lambda architecture: arm64 (Graviton, cheaper) or x86_64. Match instance_type."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "max_jumps" {
  description = "Jumps that may be up at the same time (1 to 10); Start is refused beyond it."
  type        = number
  default     = 3

  validation {
    condition     = var.max_jumps >= 1 && var.max_jumps <= 10
    error_message = "max_jumps: 1 to 10."
  }
}

variable "idle_shutdown_minutes" {
  description = "A jump terminates itself after this many minutes with no SSM session (1 to max_session_minutes)."
  type        = number
  default     = 30

  validation {
    condition     = var.idle_shutdown_minutes >= 1 && var.idle_shutdown_minutes <= var.max_session_minutes
    error_message = "idle_shutdown_minutes: 1 to max_session_minutes."
  }
}

variable "max_session_minutes" {
  description = "A jump is terminated this many minutes after launch, in use or not (5 to 10080): the bound on what one forgotten jump costs, and the most its lease (+1h from the page) can reach. Fargate/EC2 have no platform limit; this is your own guardrail."
  type        = number
  default     = 480

  validation {
    condition     = var.max_session_minutes >= 5 && var.max_session_minutes <= 10080
    error_message = "max_session_minutes: 5 to 10080 (one week)."
  }
}

variable "function_url_auth" {
  description = "How the Function URL is protected. NONE = public URL, the Lambda checks http_auth / cloudflare_auth. AWS_IAM = AWS checks SigV4 first (the browser UI cannot sign requests, so it is unusable)."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "log_retention_days" {
  description = "Days the Lambda's logs (CloudWatch) are kept."
  type        = number
  default     = 14
}

variable "force_destroy" {
  description = "true = terraform destroy deletes the lease bucket with everything in it."
  type        = bool
  default     = true
}
