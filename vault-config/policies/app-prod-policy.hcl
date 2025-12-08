path "secret/data/prod/app/*" {
  capabilities = ["read"] # Strict: no list in prod
}

# Explicitly deny all metadata, admin, system, and auth management paths
path "secret/metadata/prod/app/*" {
  capabilities = ["deny"]
}

path "secret/data/prod/admin/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}

path "auth/*" {
  capabilities = ["deny"]
}
