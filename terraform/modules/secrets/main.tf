# ------------------------------------------------------------------------------
# Secrets Manager — Application Secret
# ------------------------------------------------------------------------------
# Demonstrates the pattern for securely delivering secrets to EC2 instances
# via IAM role + Secrets Manager (not baked into AMIs or user data).
#
# In production:
#   - Enable automatic rotation with a Lambda rotation function
#   - Use a KMS CMK (not the default key) for cross-account access patterns
#   - Scope resource policies per consuming account/role
#
# The secret value is a sample JSON blob. Ansible will configure the app to
# read it at runtime using the AWS SDK, never writing it to disk.
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.project}/${var.environment}/app-secret"
  description             = "Sample application secret for the ${var.project} ${var.environment} environment"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-app-secret"
  })
}

# ------------------------------------------------------------------------------
# Secret Value
# ------------------------------------------------------------------------------
# Sample JSON payload simulating a database connection string and API key.
# In a real deployment, this would be populated by an external process
# (e.g., Vault, CI pipeline, or a rotation Lambda) — never hardcoded.
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    db_host     = "rewards-db.internal.${var.environment}"
    db_port     = 5432
    db_name     = "rewards"
    db_username = "app_user"
    db_password = "SAMPLE_PASSWORD_REPLACE_IN_PROD"
    api_key     = "sk-sample-api-key-for-demo-purposes"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
