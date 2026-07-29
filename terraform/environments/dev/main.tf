module "networking" {
  source = "../../modules/networking"

  environment          = var.environment
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  enable_vpc_endpoints = true

  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
}

module "iam" {
  source = "../../modules/iam"

  environment = var.environment
  project     = var.project
  github_repo = var.github_repo

  kms_key_arn = module.secretsmanager.kms_key_arn
  secret_arns = values(module.secretsmanager.secret_arns)
}

module "secretsmanager" {
  source = "../../modules/secrets-manager"

  environment           = var.environment
  project               = var.project
  kms_key_deletion_days = 7
  enable_rotation       = false
  app_iam_role_arn      = module.iam.app_role_arn
  database_username     = "dev_db_user"
}

module "vault" {
  source = "../../modules/vault"

  environment   = var.environment
  region        = var.region
  vpc_id        = module.networking.vpc_id
  subnet_id     = module.networking.private_subnet_ids[0]
  instance_type = "t3.small"
}
