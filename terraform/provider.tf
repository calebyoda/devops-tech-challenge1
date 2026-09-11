# Tells Terraform which "provider" (cloud platform) we're working with,
# and pins it to a specific version so builds stay consistent over time
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0"
    }
  }
}

# Configures the AWS provider itself — which region to build resources in.
# var.aws_region doesn't exist yet; we'll define it in variables.tf shortly.
# Terraform won't complain about this until we actually run a command.
provider "aws" {
  region = var.aws_region
}