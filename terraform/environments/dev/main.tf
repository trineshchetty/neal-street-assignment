# ------------------------------------------------------------------------------
# Dev Environment — Module Composition
# ------------------------------------------------------------------------------

locals {
  common_tags = {
    environment = var.environment
    service     = var.service
    owner       = var.owner
    cost_center = var.cost_center
    project     = var.project
  }
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
  tags                = local.common_tags
}
