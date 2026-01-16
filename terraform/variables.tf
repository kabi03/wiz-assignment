// AWS region for all resources.
variable "region" {
  type    = string
  default = "us-east-1"
}

// Name prefix used for resource naming.
variable "name" {
  type    = string
  default = "wiz-exercise"
}

// CIDRs allowed to reach the EKS public API endpoint.
variable "eks_public_access_cidrs" {
  type    = list(string)
  // Wide-open by default for lab convenience; tighten for real use.
  default = ["0.0.0.0/0"]
}

// GuardDuty detector toggle for this account/region.
variable "create_guardduty_detector" {
  type    = bool
  // Optional so labs can skip paid services if desired.
  default = false
}

// Security Hub enablement toggle.
variable "enable_securityhub" {
  type    = bool
  // Optional so labs can skip paid services if desired.
  default = false
}
