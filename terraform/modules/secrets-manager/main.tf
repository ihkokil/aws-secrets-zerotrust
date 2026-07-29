data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.name

  recovery_window = var.environment == "prod" ? 30 : 0

  common_tags = merge(
    var.tags,
    {
      Environment        = var.environment
      Project            = var.project
      ManagedBy          = "Terraform"
      DataClassification = "Sensitive"
    }
  )
}

# 1. KMS Customer Managed Key (CMK)
data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowAppRoleDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.app_iam_role_arn != "*" ? var.app_iam_role_arn : "arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "secrets_key" {
  description             = "KMS Customer Managed Key for ${local.name_prefix} secrets"
  deletion_window_in_days = var.kms_key_deletion_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secrets-kms-key"
  })
}

resource "aws_kms_alias" "secrets_key_alias" {
  name          = "alias/${var.project}/${var.environment}/secrets"
  target_key_id = aws_kms_key.secrets_key.key_id
}

# 2. Secrets Manager Secrets
# Path convention: <project>/<environment>/app/<secret_name>

resource "aws_secretsmanager_secret" "database" {
  name                    = "${var.project}/${var.environment}/app/database"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = local.recovery_window

  tags = merge(local.common_tags, {
    SecretType = "DatabaseCredentials"
  })
}

resource "aws_secretsmanager_secret_version" "database_val" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    username = var.database_username
    password = "InitialSecurePassword123!#ChangeMe"
    host     = "db-${var.environment}.${var.project}.internal"
    port     = "5432"
    engine   = "postgres"
  })
}

resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "${var.project}/${var.environment}/app/api-keys"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = local.recovery_window

  tags = merge(local.common_tags, {
    SecretType = "APIKeys"
  })
}

resource "aws_secretsmanager_secret_version" "api_keys_val" {
  secret_id = aws_secretsmanager_secret.api_keys.id
  secret_string = jsonencode({
    third_party_api_key = "sk_live_demo_key_9876543210"
    webhook_secret      = "whsec_demosecret_abcdef123456"
  })
}

resource "aws_secretsmanager_secret" "config" {
  name                    = "${var.project}/${var.environment}/app/config"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = local.recovery_window

  tags = merge(local.common_tags, {
    SecretType = "Configuration"
  })
}

resource "aws_secretsmanager_secret_version" "config_val" {
  secret_id = aws_secretsmanager_secret.config.id
  secret_string = jsonencode({
    feature_flags = {
      enable_zero_trust_v2 = true
      enable_cache_ttl     = true
      max_retries          = 5
    }
  })
}

# 3. Secret Resource Policy: Deny non-MFA human access
data "aws_iam_policy_document" "secret_policy_doc" {
  statement {
    sid       = "DenyNonMFAHumanAccess"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_secretsmanager_secret_policy" "db_policy" {
  secret_arn = aws_secretsmanager_secret.database.arn
  policy     = data.aws_iam_policy_document.secret_policy_doc.json
}

resource "aws_secretsmanager_secret_policy" "api_policy" {
  secret_arn = aws_secretsmanager_secret.api_keys.arn
  policy     = data.aws_iam_policy_document.secret_policy_doc.json
}

resource "aws_secretsmanager_secret_policy" "config_policy" {
  secret_arn = aws_secretsmanager_secret.config.arn
  policy     = data.aws_iam_policy_document.secret_policy_doc.json
}

# 4. Lambda Secret Rotation (Prod Only)
data "archive_file" "lambda_dummy" {
  type        = "zip"
  output_path = "${path.module}/dummy_lambda.zip"

  source {
    content  = "exports.handler = async (event) => { console.log('Rotation trigger:', event); return { status: 'success' }; };"
    filename = "index.js"
  }
}

resource "aws_iam_role" "lambda_rotation_role" {
  count = var.enable_rotation ? 1 : 0
  name  = "${local.name_prefix}-secret-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_lambda_function" "rotation_lambda" {
  count            = var.enable_rotation ? 1 : 0
  filename         = data.archive_file.lambda_dummy.output_path
  function_name    = "${local.name_prefix}-db-secret-rotator"
  role             = aws_iam_role.lambda_rotation_role[0].arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  source_code_hash = data.archive_file.lambda_dummy.output_base64sha256

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_rotation" "db_rotation" {
  count               = var.enable_rotation ? 1 : 0
  secret_id           = aws_secretsmanager_secret.database.id
  rotation_lambda_arn = aws_lambda_function.rotation_lambda[0].arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# 5. CloudWatch Alarms: Anomaly detection & high access rates
resource "aws_cloudwatch_metric_alarm" "high_secret_access" {
  alarm_name          = "${local.name_prefix}-high-secret-access-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GetSecretValueCount"
  namespace           = "AWS/SecretsManager"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Triggers when GetSecretValue calls exceed 10 in 5 minutes (potential anomaly)"
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}
