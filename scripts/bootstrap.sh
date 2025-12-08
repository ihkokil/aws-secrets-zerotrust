#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: bootstrap.sh
# Description: Provisions S3 bucket, DynamoDB lock table, and KMS CMK for
#              Terraform remote state storage with server-side encryption.
# ==============================================================================

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

BUCKET_NAME="tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}"
DYNAMODB_TABLE="terraform-state-lock"
KMS_ALIAS="alias/terraform-state-key"

echo "======================================================================"
echo " Bootstrapping Terraform Backend Resources"
echo " Account ID : ${AWS_ACCOUNT_ID}"
echo " Region     : ${AWS_REGION}"
echo " S3 Bucket  : ${BUCKET_NAME}"
echo " DynamoDB   : ${DYNAMODB_TABLE}"
echo "======================================================================"

# 1. Create KMS Key for Terraform state encryption
echo "[1/4] Creating KMS Customer Managed Key for S3 state encryption..."
KMS_KEY_ID=$(aws kms create-key \
  --description "KMS CMK for Terraform remote state encryption" \
  --region "${AWS_REGION}" \
  --query "KeyMetadata.KeyId" \
  --output text 2>/dev/null || true)

if [ -n "${KMS_KEY_ID}" ]; then
  aws kms create-alias \
    --alias-name "${KMS_ALIAS}" \
    --target-key-id "${KMS_KEY_ID}" \
    --region "${AWS_REGION}" 2>/dev/null || true
  echo "  ✓ KMS Key created: ${KMS_KEY_ID} (${KMS_ALIAS})"
else
  echo "  ℹ KMS key alias ${KMS_ALIAS} already exists or error occurred."
  KMS_KEY_ID=$(aws kms describe-key --key-id "${KMS_ALIAS}" --query "KeyMetadata.KeyId" --output text)
fi

# Enable key rotation
aws kms enable-key-rotation --key-id "${KMS_KEY_ID}" --region "${AWS_REGION}"

# 2. Create S3 Bucket for state storage
echo "[2/4] Creating S3 state bucket: ${BUCKET_NAME}..."
if [ "${AWS_REGION}" == "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  ℹ S3 Bucket may already exist."
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>/dev/null || echo "  ℹ S3 Bucket may already exist."
fi

# Enable Bucket Versioning
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# Enable Default KMS Encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "'"${KMS_ALIAS}"'"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

# Block Public Access
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'
echo "  ✓ S3 Bucket configured with versioning, encryption, and public access blocked."

# 3. Create DynamoDB Table for State Locking
echo "[3/4] Creating DynamoDB table: ${DYNAMODB_TABLE}..."
aws dynamodb create-table \
  --table-name "${DYNAMODB_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${AWS_REGION}" 2>/dev/null || echo "  ℹ DynamoDB table may already exist."

echo "  ✓ DynamoDB state locking table ready."

# 4. Display Backend Configuration Snippet
echo "[4/4] Remote backend setup complete!"
echo "----------------------------------------------------------------------"
echo "Terraform backend config block:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    key            = \"secrets-zerotrust/<env>/terraform.tfstate\""
echo "    region         = \"${AWS_REGION}\""
echo "    dynamodb_table = \"${DYNAMODB_TABLE}\""
echo "    encrypt        = true"
echo "    kms_key_id     = \"${KMS_ALIAS}\""
echo "  }"
echo "}"
echo "----------------------------------------------------------------------"
