// Terraform version and provider pins.
terraform {
  required_version = ">= 1.5.0"

  // Provider versions pinned for reproducible builds.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5.0"
    }
  }
}

// AWS provider configuration.
provider "aws" {
  region = var.region

  // Ignore AWS program tags that can cause drift.
  ignore_tags {
    keys = ["aws-apn-id"]
  }
}
