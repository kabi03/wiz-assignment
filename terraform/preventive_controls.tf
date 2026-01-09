# terraform/preventive_controls.tf

# Preventative control: ensure new EBS volumes are encrypted by default.
# Cheap, simple, and easy to explain in the panel.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
