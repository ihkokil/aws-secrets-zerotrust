output "app_role_arn" {
  value       = aws_iam_role.app_role.arn
  description = "ARN of app role assumed via IRSA or instance profile"
}

output "ci_role_arn" {
  value       = aws_iam_role.ci_role.arn
  description = "ARN of CI/CD role assumed via GitHub Actions OIDC"
}

output "rotation_lambda_role_arn" {
  value       = aws_iam_role.rotation_lambda_role.arn
  description = "ARN of Lambda role for secret rotation"
}

output "readonly_role_arn" {
  value       = aws_iam_role.readonly_role.arn
  description = "ARN of read-only auditor role requiring MFA"
}

output "app_instance_profile_arn" {
  value       = aws_iam_instance_profile.app_profile.arn
  description = "ARN of EC2 instance profile for app"
}
