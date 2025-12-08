terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tfstate-account-us-east-1"
    key            = "secrets-zerotrust/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment        = var.environment
      Project            = var.project
      ManagedBy          = "Terraform"
      DataClassification = "Sensitive"
    }
  }
}
