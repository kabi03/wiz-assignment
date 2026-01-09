variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "wiz-exercise"
}

# For EKS API endpoint access. For simplicity default is open.
# For a better demo, set this to your public IP /32.
variable "eks_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# GuardDuty: only one detector per account/region.
# If your account already has GuardDuty enabled, creating one will fail.
# Leave false unless you know you need Terraform to create it.
variable "create_guardduty_detector" {
  type    = bool
  default = false
}

variable "enable_securityhub" {
  type    = bool
  default = false
}
