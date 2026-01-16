// Remote state backend configuration for this stack.
terraform {
  // Backend details are supplied via terraform init -backend-config.
  // This keeps state locations and credentials out of the main code.
  backend "s3" {}
}
