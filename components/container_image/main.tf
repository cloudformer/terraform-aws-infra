# A container image built from a local directory with Docker and pushed to an ECR repository, for arm64 and x86_64
# (tags <tag>-arm64 / <tag>-x86_64). Rebuilt only when tag changes: make it a hash of the build context.

locals {
  image    = "${var.repository_url}:${var.tag}"
  registry = split("/", var.repository_url)[0]
  platform = { arm64 = "linux/arm64", x86_64 = "linux/amd64" }
  # one `docker buildx build ... --push` per architecture, joined into the provisioner's script
  builds = join("\n", [for a in var.architectures :
  "docker buildx build --platform ${local.platform[a]} --provenance=false ${join(" ", [for k, val in var.build_args : "--build-arg ${k}=${val}"])} -t \"$IMAGE-${a}\" --push \"$CONTEXT\""])
}

# the provider's credentials log Docker in to ECR: no AWS CLI needed, and the token (valid 12 hours for every
# repository the caller may use) never reaches the state or any file: ephemeral, it lives only during the apply.
# build = false: nothing here exists (mock tests, which cannot mock ephemeral resources; images pushed elsewhere).
ephemeral "aws_ecr_authorization_token" "this" {
  count = var.build ? 1 : 0
}

# Builds and pushes both architectures on this machine (Docker running), only when the image's build context
# changes (the tag is its content hash): switching var.architecture later needs no rebuild. The login goes to a
# throw-away DOCKER_CONFIG, so whatever credential store ~/.docker/config.json names is neither used nor
# changed; the current context's daemon and the installed CLI plugins still are.
resource "terraform_data" "image" {
  count            = var.build ? 1 : 0
  input            = local.image
  triggers_replace = [local.image, local.builds]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      export DOCKER_HOST="$(docker context inspect --format '{{.Endpoints.docker.Host}}')"
      export DOCKER_CONFIG="$(mktemp -d)"
      trap 'rm -rf "$DOCKER_CONFIG"' EXIT
      echo '{}' > "$DOCKER_CONFIG/config.json"
      [ -d "$HOME/.docker/cli-plugins" ] && ln -s "$HOME/.docker/cli-plugins" "$DOCKER_CONFIG/cli-plugins"
      printf '%s' "$ECR_PASSWORD" | docker login --username AWS --password-stdin "$REGISTRY"
      ${local.builds}
    EOT
    environment = {
      ECR_PASSWORD = ephemeral.aws_ecr_authorization_token.this[0].password
      REGISTRY     = local.registry
      IMAGE        = local.image
      CONTEXT      = var.context
    }
  }
}
