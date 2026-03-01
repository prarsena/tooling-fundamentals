# =============================================================================
# terraform/supporting_files/variables.tf
# Input variable declarations for the root module.
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Short identifier used in resource names and tags."
  type        = string
  default     = "devops-stack"
}
