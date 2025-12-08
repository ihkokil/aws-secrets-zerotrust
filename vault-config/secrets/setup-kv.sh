#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: setup-kv.sh
# Description: Enables KV v2 secret engine in Vault and seeds initial secrets.
# ==============================================================================

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

echo "======================================================================"
echo " Setting up Vault KV v2 Secrets Engine"
echo " Vault Address: ${VAULT_ADDR}"
echo "======================================================================"

# Enable KV v2 engine at path "secret/"
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "  ℹ KV v2 engine already enabled at secret/"

# Seed Dev Database Secret
echo "Seeding secret/data/dev/app/database..."
vault kv put secret/dev/app/database \
  username="dev_vault_user" \
  password="DevVaultSecurePassword123!" \
  host="dev-db.internal.local" \
  port="5432"

# Seed Dev API Keys Secret
echo "Seeding secret/data/dev/app/api-keys..."
vault kv put secret/dev/app/api-keys \
  third_party_api_key="sk_vault_dev_key_12345" \
  webhook_secret="whsec_vault_dev_secret_67890"

# Seed Prod Secrets
echo "Seeding secret/data/prod/app/database..."
vault kv put secret/prod/app/database \
  username="prod_vault_admin" \
  password="ProdVaultSuperSecretPassword99!" \
  host="prod-db.internal.local" \
  port="5432"

echo "✓ Vault KV v2 secret setup complete!"
