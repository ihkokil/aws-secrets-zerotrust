data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition

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

# ==============================================================================
# 1. APP ROLE (IRSA & Instance Profile)
# ==============================================================================

# Trust Policy for EKS IRSA and EC2 fallback
data "aws_iam_policy_document" "app_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${var.cluster_oidc_issuer_url}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.cluster_oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.cluster_oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_role" {
  name               = "${local.name_prefix}-app-role"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "app_policy" {
  statement {
    sid       = "AllowSecretRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }

  statement {
    sid       = "AllowKMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "ExplicitDenyMutation"
    effect    = "Deny"
    actions   = ["secretsmanager:DeleteSecret", "secretsmanager:PutSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_policy" {
  name        = "${local.name_prefix}-app-policy"
  description = "Least privilege read-only access to secrets for app"
  policy      = data.aws_iam_policy_document.app_policy.json
}

resource "aws_iam_role_policy_attachment" "app_attach" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.app_policy.arn
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${local.name_prefix}-app-instance-profile"
  role = aws_iam_role.app_role.name
}

# ==============================================================================
# 2. CI/CD ROLE (GitHub Actions OIDC)
# ==============================================================================

data "aws_iam_policy_document" "ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "ci_role" {
  name               = "${local.name_prefix}-ci-role"
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "ci_policy" {
  statement {
    sid       = "AllowSecretSeeding"
    effect    = "Allow"
    actions   = ["secretsmanager:PutSecretValue", "secretsmanager:CreateSecret", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }

  statement {
    sid       = "AllowECRPush"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }

  statement {
    sid       = "ExplicitDenySecretRead"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_policy" {
  name        = "${local.name_prefix}-ci-policy"
  description = "CI role policy allowing secret seeding and image pushing, explicitly denying secret reading"
  policy      = data.aws_iam_policy_document.ci_policy.json
}

resource "aws_iam_role_policy_attachment" "ci_attach" {
  role       = aws_iam_role.ci_role.name
  policy_arn = aws_iam_policy.ci_policy.arn
}

# ==============================================================================
# 3. ROTATION LAMBDA ROLE
# ==============================================================================

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda_role" {
  name               = "${local.name_prefix}-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "AllowSecretRotation"
    effect    = "Allow"
    actions   = ["secretsmanager:RotateSecret", "secretsmanager:PutSecretValue", "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }

  statement {
    sid       = "AllowKMSDataKey"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "AllowVPCExecution"
    effect    = "Allow"
    actions   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.name_prefix}-lambda-policy"
  description = "Policy for secret rotation lambda"
  policy      = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.rotation_lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ==============================================================================
# 4. READONLY AUDITOR ROLE (MFA Required)
# ==============================================================================

data "aws_iam_policy_document" "readonly_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "readonly_role" {
  name               = "${local.name_prefix}-readonly-auditor-role"
  assume_role_policy = data.aws_iam_policy_document.readonly_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "readonly_policy" {
  statement {
    sid       = "AllowMetadataListingWithMFA"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid       = "ExplicitDenySecretValueRead"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "readonly_policy" {
  name        = "${local.name_prefix}-readonly-auditor-policy"
  description = "Policy for human auditors requiring MFA and denying secret retrieval"
  policy      = data.aws_iam_policy_document.readonly_policy.json
}

resource "aws_iam_role_policy_attachment" "readonly_attach" {
  role       = aws_iam_role.readonly_role.name
  policy_arn = aws_iam_policy.readonly_policy.arn
}
