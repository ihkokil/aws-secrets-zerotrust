variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
}

variable "project" {
  type        = string
  description = "Project name identifier"
  default     = "myapp"
}

variable "cluster_oidc_issuer_url" {
  type        = string
  description = "EKS cluster OIDC issuer URL (without https://)"
  default     = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE123456789"
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace for app"
  default     = "secrets-demo"
}

variable "k8s_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for app IRSA"
  default     = "secrets-demo-sa"
}

variable "secret_arns" {
  type        = list(string)
  description = "List of Secret ARNs the app role can access"
  default     = ["*"]
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for secret decryption"
  default     = "*"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository formatted as org/repo for OIDC trust"
  default     = "YOUR_ORGANIZATION/aws-secrets-zerotrust"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
