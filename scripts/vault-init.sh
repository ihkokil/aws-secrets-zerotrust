#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: vault-init.sh
# Description: Initializes HashiCorp Vault on EC2 node and secures root token
#              and unseal keys in AWS Secrets Manager.
# ==============================================================================

ENV="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

SECRET_ID="myapp/${ENV}/vault/unseal-keys"

echo "======================================================================"
echo " Initializing Vault & Securing Unseal Keys"
echo " Vault Address: ${VAULT_ADDR}"
echo " Secret Path  : ${SECRET_ID}"
echo "======================================================================"

export VAULT_ADDR="${VAULT_ADDR}"

if vault status | grep -q "Initialized.*true"; then
  echo "ℹ Vault is already initialized."
  exit 0
fi

echo "[1/3] Initializing Vault operator..."
INIT_PAYLOAD=$(vault operator init -format=json)

echo "[2/3] Storing unseal keys and root token in Secrets Manager..."
aws secretsmanager put-secret-value \
  --secret-id "${SECRET_ID}" \
  --secret-string "${INIT_PAYLOAD}" \
  --region "${AWS_REGION}"

echo "[3/3] Vault initialized successfully. Bootstrap root credentials saved to AWS Secrets Manager."
echo "✓ Remember: Root token should be revoked after initial auth setup is complete!"
