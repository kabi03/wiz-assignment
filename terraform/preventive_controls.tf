// Preventative control to encrypt new EBS volumes in this region.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
