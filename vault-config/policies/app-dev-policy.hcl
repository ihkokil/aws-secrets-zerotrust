path "secret/data/dev/app/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/dev/app/*" {
  capabilities = ["read", "list"]
}

# Explicitly deny admin & sensitive paths
path "secret/data/dev/admin/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}

path "auth/*" {
  capabilities = ["deny"]
}
