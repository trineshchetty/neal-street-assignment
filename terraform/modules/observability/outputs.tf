output "app_log_group_name" {
  description = "CloudWatch log group name for application logs — pass to compute/Ansible"
  value       = aws_cloudwatch_log_group.app.name
}

output "system_log_group_name" {
  description = "CloudWatch log group name for system logs"
  value       = aws_cloudwatch_log_group.system.name
}

output "unhealthy_hosts_alarm_arn" {
  description = "ARN of the unhealthy hosts alarm"
  value       = aws_cloudwatch_metric_alarm.unhealthy_hosts.arn
}

output "elb_5xx_alarm_arn" {
  description = "ARN of the ELB 5xx alarm"
  value       = aws_cloudwatch_metric_alarm.elb_5xx.arn
}
