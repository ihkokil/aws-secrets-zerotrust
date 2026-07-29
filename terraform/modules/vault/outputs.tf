output "vault_instance_id" {
  value       = aws_instance.vault.id
  description = "EC2 Instance ID hosting self-hosted Vault"
}

output "vault_private_ip" {
  value       = aws_instance.vault.private_ip
  description = "Private IP address of Vault EC2 instance"
}

output "vault_endpoint" {
  value       = "http://${aws_instance.vault.private_ip}:8200"
  description = "Private endpoint URL for Vault"
}

output "vault_kms_key_arn" {
  value       = aws_kms_key.vault_unseal.arn
  description = "KMS Key ARN used for Vault auto-unseal"
}

output "vault_unseal_secret_arn" {
  value       = aws_secretsmanager_secret.vault_unseal_keys.arn
  description = "Secrets Manager ARN storing Vault bootstrap unseal keys and root token"
}
