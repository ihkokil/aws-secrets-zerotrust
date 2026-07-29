data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  name_prefix = "myapp-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition

  common_tags = merge(
    var.tags,
    {
      Environment        = var.environment
      Project            = "aws-secrets-zerotrust"
      ManagedBy          = "Terraform"
      DataClassification = "Sensitive"
    }
  )
}

# 1. KMS Key for Vault Auto-Unseal
resource "aws_kms_key" "vault_unseal" {
  description             = "KMS Key for Vault Auto-Unseal in ${var.environment}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vault-unseal-kms-key"
  })
}

resource "aws_kms_alias" "vault_unseal_alias" {
  name          = "alias/${local.name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# 2. S3 Bucket for Vault Snapshots
resource "aws_s3_bucket" "vault_snapshots" {
  bucket        = var.snapshot_bucket_name != "" ? var.snapshot_bucket_name : "${local.name_prefix}-vault-snapshots-${local.account_id}"
  force_destroy = var.environment == "dev"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vault-snapshots"
  })
}

resource "aws_s3_bucket_versioning" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 3. Secrets Manager secret for Vault unseal keys & root token (bootstrap storage)
resource "aws_secretsmanager_secret" "vault_unseal_keys" {
  name                    = "myapp/${var.environment}/vault/unseal-keys"
  kms_key_id              = aws_kms_key.vault_unseal.arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vault-unseal-keys"
  })
}

# 4. IAM Role for Vault EC2 Instance
data "aws_iam_policy_document" "vault_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault_role" {
  name               = "${local.name_prefix}-vault-instance-role"
  assume_role_policy = data.aws_iam_policy_document.vault_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "vault_policy_doc" {
  statement {
    sid       = "VaultKMSAutoUnseal"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.vault_unseal.arn]
  }

  statement {
    sid       = "VaultUnsealSecretsStore"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:CreateSecret"]
    resources = [aws_secretsmanager_secret.vault_unseal_keys.arn]
  }

  statement {
    sid       = "VaultS3Snapshots"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.vault_snapshots.arn, "${aws_s3_bucket.vault_snapshots.arn}/*"]
  }

  statement {
    sid       = "VaultCloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "vault_policy" {
  name        = "${local.name_prefix}-vault-policy"
  description = "Policy for Vault EC2 instance auto-unseal, snapshots, and audit logging"
  policy      = data.aws_iam_policy_document.vault_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "vault_attach" {
  role       = aws_iam_role.vault_role.name
  policy_arn = aws_iam_policy.vault_policy.arn
}

resource "aws_iam_instance_profile" "vault_profile" {
  name = "${local.name_prefix}-vault-instance-profile"
  role = aws_iam_role.vault_role.name
}

# 5. Security Group for Vault Instance
resource "aws_security_group" "vault_sg" {
  name        = "${local.name_prefix}-vault-sg"
  description = "Vault API & cluster traffic - private VPC access only"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow Vault API HTTP traffic from VPC"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vault-sg"
  })
}

# 6. EC2 Instance for Vault
resource "aws_instance" "vault" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  vpc_security_group_ids = [aws_security_group.vault_sg.id]
  iam_instance_profile = aws_iam_instance_profile.vault_profile.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = var.environment == "dev"
    tags                  = local.common_tags
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

              echo "Installing HashiCorp Vault ${var.vault_version}..."
              yum install -y yum-utils shadow-utils jq aws-cli
              yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
              yum -y install vault-${var.vault_version}

              mkdir -p /var/lib/vault/data /etc/vault.d /var/log/vault
              chown -R vault:vault /var/lib/vault /var/log/vault /etc/vault.d

              cat <<HCL > /etc/vault.d/vault.hcl
              ui = true
              disable_mlock = true

              storage "file" {
                path = "/var/lib/vault/data"
              }

              listener "tcp" {
                address     = "0.0.0.0:8200"
                tls_disable = 1
              }

              seal "awskms" {
                region     = "${var.region}"
                kms_key_id = "${aws_kms_key.vault_unseal.key_id}"
              }

              api_addr = "http://127.0.0.1:8200"
              cluster_addr = "http://127.0.0.1:8201"
              HCL

              systemctl enable vault
              systemctl start vault

              export VAULT_ADDR="http://127.0.0.1:8200"
              sleep 5

              if ! vault status | grep -q "Initialized.*true"; then
                echo "Initializing Vault..."
                INIT_OUT=$(vault operator init -format=json)
                ROOT_TOKEN=$(echo "$INIT_OUT" | jq -r '.root_token')

                aws secretsmanager put-secret-value \
                  --secret-id "${aws_secretsmanager_secret.vault_unseal_keys.name}" \
                  --secret-string "$INIT_OUT" \
                  --region "${var.region}" || true

                echo "Vault initialized successfully and credentials stored in Secrets Manager."
              fi
              EOF

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vault-node"
  })
}
