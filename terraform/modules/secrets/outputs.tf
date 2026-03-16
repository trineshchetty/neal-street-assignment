output "secret_arn" {
  description = "ARN of the Secrets Manager secret — pass to compute module for IAM policy scoping"
  value       = aws_secretsmanager_secret.app.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret — used by the app to retrieve the value at runtime"
  value       = aws_secretsmanager_secret.app.name
}
