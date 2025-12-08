#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: rotate-secret.sh
# Description: Demonstrates manual secret rotation in Vault KV v2 engine.
# ==============================================================================

ENV="${1:-dev}"
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

NEW_PASSWORD="RotatedPassword_$(date +%s)_Secured!"

echo "======================================================================"
echo " Demonstrating Vault Secret Rotation"
echo " Environment : ${ENV}"
echo " Path        : secret/data/${ENV}/app/database"
echo "======================================================================"

echo "[1/2] Writing updated version of secret to Vault..."
vault kv put "secret/${ENV}/app/database" \
  username="${ENV}_db_user" \
  password="${NEW_PASSWORD}" \
  host="${ENV}-db.internal.local" \
  port="5432"

echo "[2/2] Verifying new version metadata..."
vault kv metadata get "secret/${ENV}/app/database"

echo "✓ Secret successfully rotated in Vault!"
