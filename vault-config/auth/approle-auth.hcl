# HashiCorp Vault AppRole Auth Method Configuration Reference (Local Dev Fallback)

# 1. Enable AppRole Auth Method
vault auth enable approle

# 2. Configure AppRole for local app testing
vault write auth/approle/role/local-dev-role \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40 \
    token_policies="app-dev-policy"

# 3. Retrieve Role ID and Secret ID for local dev
vault read auth/approle/role/local-dev-role/role-id
vault write -f auth/approle/role/local-dev-role/secret-id
