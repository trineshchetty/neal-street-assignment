# ------------------------------------------------------------------------------
# Networking Outputs
# ------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.networking.private_subnet_id
}

# ------------------------------------------------------------------------------
# Compute Outputs
# ------------------------------------------------------------------------------

output "instance_ids" {
  description = "IDs of the EC2 instances"
  value       = module.compute.instance_ids
}

output "ec2_security_group_id" {
  description = "Security group ID attached to EC2 instances"
  value       = module.compute.security_group_id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

# ------------------------------------------------------------------------------
# Load Balancer Outputs
# ------------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the ALB — curl this to hit the health endpoint"
  value       = module.loadbalancer.alb_dns_name
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = module.loadbalancer.target_group_arn
}

# ------------------------------------------------------------------------------
# Secrets Outputs
# ------------------------------------------------------------------------------

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = module.secrets.secret_arn
  sensitive   = true
}

output "secret_name" {
  description = "Name of the Secrets Manager secret (for Ansible/app config)"
  value       = module.secrets.secret_name
}

# ------------------------------------------------------------------------------
# Observability Outputs
# ------------------------------------------------------------------------------

output "app_log_group_name" {
  description = "CloudWatch log group for application logs"
  value       = module.observability.app_log_group_name
}

output "system_log_group_name" {
  description = "CloudWatch log group for system logs"
  value       = module.observability.system_log_group_name
}
