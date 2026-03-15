# ------------------------------------------------------------------------------
# Dev Environment Values
# ------------------------------------------------------------------------------
# To promote to prod: copy this file, change values, and create
# terraform/environments/prod/ with its own backend key.
# ------------------------------------------------------------------------------

region      = "eu-west-1"
environment = "dev"
project     = "neal-street"
service     = "rewards"
owner       = "candidate"
cost_center = "payments"

# Networking — single AZ, small CIDRs for dev
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.10.0/24"
availability_zone   = "eu-west-1a"
