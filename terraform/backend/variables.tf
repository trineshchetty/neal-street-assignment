variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "neal-street"
}

variable "region" {
  description = "AWS region for state backend resources"
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Common tags applied to all backend resources"
  type        = map(string)
  default = {
    environment = "shared"
    service     = "terraform-state"
    owner       = "candidate"
    cost_center = "payments"
    managed_by  = "terraform"
  }
}
