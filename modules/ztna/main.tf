# ztna: a Lambda console (Function URL) that launches on-demand EC2 jump hosts from a launch template into a chosen
# network profile, writes each one's lease, and terminates them. The jump is stateless (always terminated); you
# connect through SSM Session Manager. The jump agent (user-data) self-terminates on lease end / idle.

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p               = var.project_name
  package         = "ztna==${var.ztna_version}"
  ssh_user        = "ec2-user" # Amazon Linux 2023
  default_network = var.default_network != "" ? var.default_network : keys(var.networks)[0]
  # the NETWORKS env the Lambda reads: {name = {subnets, groups, public}}
  networks_env = { for k, v in var.networks : k => { subnets = v.subnets, groups = v.security_group_ids, public = v.public } }
}

# ---------------- lease bucket ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = "${local.p}-${data.aws_caller_identity.me.account_id}"
  force_destroy = var.force_destroy
  versioning    = false
}

resource "aws_s3_bucket_lifecycle_configuration" "leases" {
  bucket = module.bucket.name
  rule {
    id     = "expire-leases"
    status = "Enabled"
    filter { prefix = "leases/" }
    expiration { days = 7 }
  }
}

# ---------------- package: ztna from PyPI, zipped for the Lambda ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, "${path.module}/.build/ztna"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.code
  output_path = "${path.module}/.build/ztna.zip"
  excludes    = ["**/__pycache__/**", "**/*.dist-info/**", "**/*.egg-info/**"]
}

# ---------------- the jump AMI, its IAM role, and the launch template ----------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-${var.architecture}"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_iam_role" "jump" {
  name = "${local.p}-jump-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# SSM Session Manager (the only way in: no inbound, no SSH key)
resource "aws_iam_role_policy_attachment" "jump_ssm" {
  role       = aws_iam_role.jump.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# the jump reads its own lease and terminates itself (its own agent)
resource "aws_iam_role_policy" "jump" {
  name = "${local.p}-jump-policy"
  role = aws_iam_role.jump.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${module.bucket.arn}/leases/*" },
      { Effect = "Allow", Action = ["ec2:TerminateInstances"], Resource = "*",
      Condition = { StringEquals = { "ec2:ResourceTag/Project" = local.p } } },
    ]
  })
}

resource "aws_iam_instance_profile" "jump" {
  name = "${local.p}-jump"
  role = aws_iam_role.jump.name
}

resource "aws_launch_template" "jump" {
  name_prefix   = "${local.p}-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.jump.arn }
  metadata_options { http_tokens = "required" } # IMDSv2 only

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -e
    cat > /etc/ztna.env <<'ENV'
    BUCKET=${module.bucket.name}
    IDLE_MINUTES=${var.idle_shutdown_minutes}
    REGION=${data.aws_region.current.name}
    ENV
    cat > /usr/local/bin/ztna-agent <<'AGENT'
    ${file("${path.module}/jump-agent.sh")}
    AGENT
    chmod +x /usr/local/bin/ztna-agent
    cat > /etc/systemd/system/ztna-agent.service <<'UNIT'
    [Unit]
    Description=ztna jump agent
    After=amazon-ssm-agent.service
    [Service]
    ExecStart=/usr/local/bin/ztna-agent
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now ztna-agent
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Project = local.p }
  }
}

# ---------------- the Lambda console ----------------
module "server" {
  source = "../../components/lambda"

  function_name      = "${local.p}-lambda"
  filename           = data.archive_file.code.output_path
  source_code_hash   = data.archive_file.code.output_base64sha256
  handler            = "ztna.server.lambda_function.lambda_handler"
  runtime            = "python3.12"
  architecture       = var.architecture
  timeout            = 30
  memory_size        = 256
  log_retention_days = var.log_retention_days

  function_url = true
  url_auth     = var.function_url_auth

  environment = {
    BUCKET                = module.bucket.name
    PROJECT               = local.p
    LAUNCH_TEMPLATE_ID    = aws_launch_template.jump.id
    INSTANCE_TYPE         = var.instance_type
    NETWORKS              = jsonencode(local.networks_env)
    DEFAULT_NETWORK       = local.default_network
    TARGETS               = jsonencode(var.targets)
    SSH_USER              = local.ssh_user
    IDLE_SHUTDOWN_MINUTES = tostring(var.idle_shutdown_minutes)
    MAX_SESSION_MINUTES   = tostring(var.max_session_minutes)
    MAX_JUMPS             = tostring(var.max_jumps)
    HTTP_AUTH             = var.http_auth.enabled ? "1" : "0"
    USER_NAME             = var.http_auth.username
    PASSWORD              = var.http_auth.password
    CLOUDFLARE_AUTH       = var.cloudflare_auth.enabled ? "1" : "0"
    CLOUDFLARE_TEAM       = var.cloudflare_auth.team
    CLOUDFLARE_AUD        = var.cloudflare_auth.aud
  }

  # launch / describe / terminate jumps, pass the jump role, read-write the lease
  policy_statements = [
    { Effect = "Allow", Action = ["ec2:RunInstances", "ec2:CreateTags", "ec2:DescribeInstances"], Resource = "*" },
    { Effect = "Allow", Action = ["ec2:TerminateInstances"], Resource = "*",
    Condition = { StringEquals = { "ec2:ResourceTag/Project" = local.p } } },
    { Effect = "Allow", Action = ["iam:PassRole"], Resource = aws_iam_role.jump.arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${module.bucket.arn}/leases/*" },
  ]
}
