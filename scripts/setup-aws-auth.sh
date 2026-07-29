#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: setup-aws-auth.sh
# Description: Configures Vault AWS IAM auth method bound to AWS IAM roles.
# ==============================================================================

ENV="${1:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
APP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/myapp-${ENV}-app-role"

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

echo "======================================================================"
echo " Configuring Vault AWS IAM Auth Method"
echo " Environment  : ${ENV}"
echo " Account ID   : ${AWS_ACCOUNT_ID}"
echo " App Role ARN : ${APP_ROLE_ARN}"
echo "======================================================================"

echo "[1/3] Enabling AWS auth method..."
vault auth enable aws 2>/dev/null || echo "  ℹ AWS auth method already enabled."

echo "[2/3] Writing policies..."
vault policy write "app-${ENV}-policy" "vault-config/policies/app-${ENV}-policy.hcl"

echo "[3/3] Creating Vault role bound to IAM principal..."
vault write "auth/aws/role/app-${ENV}" \
    auth_type=iam \
    bound_iam_principal_arn="${APP_ROLE_ARN}" \
    policies="app-${ENV}-policy" \
    ttl=1h \
    max_ttl=4h

echo "✓ Vault AWS IAM auth successfully configured for role app-${ENV}!"
