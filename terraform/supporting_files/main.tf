# =============================================================================
# terraform/supporting_files/main.tf
# Root module boilerplate. Replace/extend this with your actual resources.
# =============================================================================

terraform {
  # Minimum version requirement. OpenTofu 1.7+ is recommended for 2026.
  required_version = ">= 1.7.0"

  required_providers {
    # Example: AWS provider. Remove or swap for your target cloud.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Local provider: useful for writing files and running local commands
    # without a full cloud provider — great for bootstrapping/testing.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    # Random provider: generates random strings for unique resource names.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # --------------------------------------------------------------------------
  # Remote state backend (disabled by default — uncomment for team usage).
  # The local backend is the default; it stores state in terraform.tfstate.
  # WARNING: Never commit terraform.tfstate to Git.
  # --------------------------------------------------------------------------
  # backend "s3" {
  #   bucket = var.state_bucket
  #   key    = "global/terraform.tfstate"
  #   region = var.aws_region
  # }
}

# --------------------------------------------------------------------------
# Provider configuration
# --------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # On macOS, AWS credentials are stored in ~/.aws/credentials by the CLI.
  # The provider reads them automatically — no hardcoding required.
  # profile = "my-sso-profile"  # Uncomment to use a named AWS SSO profile.

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Repository  = "devops-stack"
    }
  }
}

# --------------------------------------------------------------------------
# Example resource: a random suffix for unique S3 bucket names.
# Replace this with your actual resource definitions.
# --------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

resource "local_file" "hello" {
  content  = "Hello from Terraform! Environment: ${var.environment}"
  filename = "${path.module}/hello.txt"
}
