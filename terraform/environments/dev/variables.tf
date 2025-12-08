variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "project" {
  type        = string
  description = "Project name identifier"
  default     = "myapp"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "github_repo" {
  type        = string
  description = "GitHub Org/Repo formatted string for CI OIDC"
  default     = "ihkokil/aws-secrets-zerotrust"
}
