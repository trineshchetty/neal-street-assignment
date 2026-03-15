# ------------------------------------------------------------------------------
# Environment Configuration
# ------------------------------------------------------------------------------

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "service" {
  description = "Service name for tagging"
  type        = string
}

variable "owner" {
  description = "Owner tag for cost/ownership tracking"
  type        = string
}

variable "cost_center" {
  description = "Cost center tag for billing attribution"
  type        = string
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
}

variable "availability_zone" {
  description = "AZ for the single-AZ dev topology"
  type        = string
}

# ------------------------------------------------------------------------------
# Compute
# ------------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances behind the ALB"
  type        = number
  default     = 1
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 80
}
