// Remote state backend configuration for this stack.
terraform {
  // Backend details are supplied via terraform init -backend-config.
  backend "s3" {}
}
