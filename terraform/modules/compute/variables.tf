variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group placement"
  type        = string
}

variable "private_subnet_id" {
  description = "Subnet ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type — t3.micro for dev, right-size for prod"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances. Start with 1 for dev, scale out by incrementing"
  type        = number
  default     = 1
}

variable "ami_id" {
  description = "AMI ID override. If empty, latest Amazon Linux 2023 is used"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port the application listens on (Gunicorn behind Nginx)"
  type        = number
  default     = 80
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB — used to restrict EC2 ingress"
  type        = string
}

variable "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret the app needs to read"
  type        = string
  default     = ""
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for application logs"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
