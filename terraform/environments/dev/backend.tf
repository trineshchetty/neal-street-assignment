# ------------------------------------------------------------------------------
# Remote State Backend
# ------------------------------------------------------------------------------
# Provisioned by terraform/backend/. Uses S3 for state storage with KMS
# encryption and DynamoDB for locking to prevent concurrent applies.
# Each environment uses a separate state key for isolation.
# ------------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "neal-street-terraform-state"
    key            = "environments/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "neal-street-terraform-locks"
    encrypt        = true
  }
}
