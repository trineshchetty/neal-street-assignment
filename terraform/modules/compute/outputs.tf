output "instance_ids" {
  description = "IDs of the EC2 instances"
  value       = aws_instance.app[*].id
}

output "private_ips" {
  description = "Private IP addresses of the EC2 instances"
  value       = aws_instance.app[*].private_ip
}

output "security_group_id" {
  description = "Security group ID attached to EC2 instances"
  value       = aws_security_group.ec2.id
}

output "iam_role_name" {
  description = "Name of the EC2 IAM role"
  value       = aws_iam_role.ec2.name
}

output "iam_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}

output "launch_template_id" {
  description = "Launch template ID for the app instances"
  value       = aws_launch_template.app.id
}
