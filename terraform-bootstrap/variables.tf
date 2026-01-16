// AWS region for the bootstrap stack.
variable "region" {
  type    = string
  // Keep in sync with the main stack region.
  default = "us-east-1"
}

// Name prefix for bootstrap resources.
variable "name" {
  type    = string
  // Used as a prefix for the state bucket and lock table.
  default = "wiz-exercise"
}
