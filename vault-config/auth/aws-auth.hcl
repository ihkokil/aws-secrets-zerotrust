# HashiCorp Vault AWS IAM Auth Method Configuration Reference
# Enforces zero-trust authentication via STS GetCallerIdentity

# 1. Enable AWS Auth Method
vault auth enable aws

# 2. Configure AWS Client Header Validation
vault write auth/aws/config/client \
    iam_server_id_header_value="vault.example.com"

# 3. Create Dev App Role (bound to dev IAM role ARN)
vault write auth/aws/role/app-dev \
    auth_type=iam \
    bound_iam_principal_arn="arn:aws:iam::ACCOUNT_ID:role/myapp-dev-app-role" \
    policies=app-dev-policy \
    ttl=1h \
    max_ttl=4h

# 4. Create Prod App Role (bound to prod IAM role ARN)
vault write auth/aws/role/app-prod \
    auth_type=iam \
    bound_iam_principal_arn="arn:aws:iam::ACCOUNT_ID:role/myapp-prod-app-role" \
    policies=app-prod-policy \
    ttl=1h \
    max_ttl=4h
