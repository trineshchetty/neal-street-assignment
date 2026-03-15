terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.environment
      service     = var.service
      owner       = var.owner
      cost_center = var.cost_center
      managed_by  = "terraform"
    }
  }
}
