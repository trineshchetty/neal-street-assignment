output "alb_dns_name" {
  description = "DNS name of the ALB — use this to access the health endpoint"
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.app.arn
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)"
  value       = aws_lb.app.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.app.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB (for CloudWatch metric dimensions)"
  value       = aws_lb.app.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group (for CloudWatch metric dimensions)"
  value       = aws_lb_target_group.app.arn_suffix
}
