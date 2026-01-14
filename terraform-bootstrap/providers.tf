// Terraform version and provider pins for bootstrap state.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

// AWS provider for the bootstrap stack in us-east-1.
provider "aws" {
  region = "us-east-1"

  ignore_tags {
    keys = ["aws-apn-id"]
  }
}
