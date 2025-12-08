variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "subnet_id" {
  type        = string
  description = "ID of private subnet for Vault instance deployment"
}

variable "instance_type" {
  type        = string
  description = "EC2 Instance type for self-hosted Vault"
  default     = "t3.small"
}

variable "vault_version" {
  type        = string
  description = "Vault binary version to install"
  default     = "1.15.2"
}

variable "kms_key_id" {
  type        = string
  description = "Optional external KMS Key ID for auto-unseal"
  default     = ""
}

variable "snapshot_bucket_name" {
  type        = string
  description = "S3 bucket name for Vault snapshots"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
