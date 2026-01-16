// ECR repository for Tasky container images.
resource "aws_ecr_repository" "app" {
  name                 = "${var.name}-tasky"
  // Mutable tags so CI can update "latest" as part of the lab.
  image_tag_mutability = "MUTABLE"

  // Enable ECR scan-on-push for basic vuln scanning.
  image_scanning_configuration {
    scan_on_push = true
  }
}
