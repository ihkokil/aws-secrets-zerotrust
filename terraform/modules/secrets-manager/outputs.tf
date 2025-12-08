output "kms_key_id" {
  value       = aws_kms_key.secrets_key.key_id
  description = "KMS Customer Managed Key ID"
}

output "kms_key_arn" {
  value       = aws_kms_key.secrets_key.arn
  description = "KMS Customer Managed Key ARN"
}

output "kms_alias_arn" {
  value       = aws_kms_alias.secrets_key_alias.arn
  description = "KMS Key Alias ARN"
}

output "secret_arns" {
  value = {
    database = aws_secretsmanager_secret.database.arn
    api_keys = aws_secretsmanager_secret.api_keys.arn
    config   = aws_secretsmanager_secret.config.arn
  }
  description = "Map of secret names to secret ARNs"
}

output "rotation_lambda_arn" {
  value       = try(aws_lambda_function.rotation_lambda[0].arn, "")
  description = "ARN of secret rotation Lambda function if enabled"
}
