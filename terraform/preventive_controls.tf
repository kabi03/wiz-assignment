// Preventative control to encrypt new EBS volumes in this region.
resource "aws_ebs_encryption_by_default" "this" {
  // Enforces default encryption for all new EBS volumes.
  enabled = true
}
