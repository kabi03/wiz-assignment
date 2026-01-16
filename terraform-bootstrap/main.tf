// Get the current account ID for unique naming.
data "aws_caller_identity" "current" {}

locals {
  // Remote state bucket name scoped to the account.
  bucket_name = "wiz-exercise-tfstate-${data.aws_caller_identity.current.account_id}"
}

// S3 bucket for Terraform state.
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name
}

// Keep state history with versioning.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

// Encrypt state at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// Block all public access to state.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// DynamoDB table for Terraform state locking.
resource "aws_dynamodb_table" "tflock" {
  name         = "wiz-exercise-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

// Name of the state bucket for backend config.
output "tfstate_bucket" {
  // Used to populate terraform/backend.hcl or CI backend config.
  value = aws_s3_bucket.tfstate.bucket
}

// Name of the DynamoDB lock table for backend config.
output "tflock_table" {
  // Used to populate terraform/backend.hcl or CI backend config.
  value = aws_dynamodb_table.tflock.name
}
