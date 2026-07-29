variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)"
}

variable "project" {
  type        = string
  description = "Project identifier name"
  default     = "myapp"
}

variable "kms_key_deletion_days" {
  type        = number
  description = "Duration in days after which key is deleted (7 dev, 30 prod)"
  default     = 30
}

variable "enable_rotation" {
  type        = bool
  description = "Whether to enable Lambda rotation for database secret"
  default     = false
}

variable "rotation_days" {
  type        = number
  description = "Number of days between automatic secret rotations"
  default     = 30
}

variable "app_iam_role_arn" {
  type        = string
  description = "ARN of the IAM role permitted to decrypt secret values"
  default     = "*"
}

variable "database_username" {
  type        = string
  description = "Database master username"
  default     = "app_admin"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
