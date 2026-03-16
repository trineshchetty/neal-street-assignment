# ------------------------------------------------------------------------------
# CloudWatch Log Groups
# ------------------------------------------------------------------------------
# Centralized log groups for application and system logs. The CloudWatch Agent
# (configured via Ansible) ships logs here from each EC2 instance.
#
# Retention is set per-environment — 7 days for dev (cost control),
# 30-90 days for prod (compliance). Logs are structured by service
# so CloudWatch Logs Insights queries can target specific streams.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/${var.environment}/app"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-app-logs"
  })
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/${var.project}/${var.environment}/system"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-system-logs"
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarms — ALB Health
# ------------------------------------------------------------------------------
# These alarms use metrics that ALB publishes natively (zero agent install).
#
# HealthyHostCount < 1 means ALL targets are down — critical, page oncall.
# HTTPCode_ELB_5XX_Count catches upstream failures the app might miss.
#
# In prod: wire alarm_actions to an SNS topic → PagerDuty/Slack integration.
# For dev, alarms exist but fire silently (visible in CloudWatch console).
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-${var.environment}-unhealthy-hosts"
  alarm_description   = "No healthy targets behind the ALB — all instances are failing health checks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Name     = "${var.project}-${var.environment}-unhealthy-hosts-alarm"
    Severity = "critical"
  })
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.project}-${var.environment}-elb-5xx"
  alarm_description   = "ALB is returning 5xx errors — investigate backend health or configuration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = merge(var.tags, {
    Name     = "${var.project}-${var.environment}-elb-5xx-alarm"
    Severity = "high"
  })
}
