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

# ------------------------------------------------------------------------------
# ALB Security Group
# ------------------------------------------------------------------------------
# Defined here (not in a module) because both the load balancer and compute
# modules reference it — avoids a circular dependency.
# ------------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-${var.environment}-alb-"
  description = "Security group for the public-facing ALB"
  vpc_id      = module.networking.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from internet"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, {
    Name = "http-inbound"
  })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_targets" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow traffic to EC2 targets"
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.compute.security_group_id

  tags = merge(local.common_tags, {
    Name = "alb-to-targets"
  })
}

# ------------------------------------------------------------------------------
# Compute
# ------------------------------------------------------------------------------

module "compute" {
  source = "../../modules/compute"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  private_subnet_id     = module.networking.private_subnet_id
  instance_type         = var.instance_type
  instance_count        = var.instance_count
  app_port              = var.app_port
  alb_security_group_id = aws_security_group.alb.id
  tags                  = local.common_tags
}
