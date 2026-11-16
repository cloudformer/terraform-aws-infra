output "image" {
  description = "<repository_url>:<tag>, known only once both architectures are pushed (build = true): append -arm64 or -x86_64."
  value       = var.build ? terraform_data.image[0].output : local.image
}
