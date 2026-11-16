output "vault_addr" {
  description = "export VAULT_ADDR=<this> for the vault CLI, the Terraform vault provider and hvac"
  value       = trimsuffix(module.proxy.url, "/")
}

output "ui_url" {
  description = "The Vault UI"
  value       = "${trimsuffix(module.proxy.url, "/")}/ui/"
}

output "bucket" {
  description = "Vault's storage"
  value       = module.bucket.name
}

output "seal" {
  value = var.seal.type
}

output "kms_key_id" {
  description = "seal = kms: the seal key (also what a Vault cluster needs to unseal migrated data); null for seal = ssm."
  value       = one(module.seal[*].key_id)
}

output "unseal_key_parameter" {
  description = "seal = ssm: the SSM SecureString holding the unseal key (written at init); null for seal = kms."
  value       = local.ssm ? local.unseal_key_parameter : null
}

output "function_name" {
  description = "The Vault function"
  value       = module.vault.function_name
}
