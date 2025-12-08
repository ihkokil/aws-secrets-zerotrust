output "vpc_id" {
  value       = module.networking.vpc_id
  description = "ID of prod VPC"
}

output "private_subnet_ids" {
  value       = module.networking.private_subnet_ids
  description = "IDs of prod private subnets"
}

output "app_role_arn" {
  value       = module.iam.app_role_arn
  description = "ARN of prod app IAM role"
}

output "ci_role_arn" {
  value       = module.iam.ci_role_arn
  description = "ARN of prod CI IAM role"
}

output "kms_key_arn" {
  value       = module.secretsmanager.kms_key_arn
  description = "ARN of prod secrets KMS key"
}

output "secret_arns" {
  value       = module.secretsmanager.secret_arns
  description = "Map of prod secret names to ARNs"
}

output "rotation_lambda_arn" {
  value       = module.secretsmanager.rotation_lambda_arn
  description = "ARN of database secret rotation Lambda function"
}

output "vault_endpoint" {
  value       = module.vault.vault_endpoint
  description = "Endpoint for prod Vault instance"
}
