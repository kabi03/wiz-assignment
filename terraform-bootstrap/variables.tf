// AWS region for the bootstrap stack.
variable "region" {
  type    = string
  default = "us-east-1"
}

// Name prefix for bootstrap resources.
variable "name" {
  type    = string
  default = "wiz-exercise"
}
