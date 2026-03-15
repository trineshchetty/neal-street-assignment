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

## For security purposes tfvars should be omitted from the repository if confidential data and secrets are defined here.
## For demo purposes I will be commiting it to the main repo
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.10.0/24"
availability_zone   = "eu-west-1a"

# Compute — t3.micro is free-tier eligible, single instance for dev
instance_type  = "t3.micro"
instance_count = 1
app_port       = 80
