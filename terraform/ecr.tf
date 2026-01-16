// ECR repository for Tasky container images.
resource "aws_ecr_repository" "app" {
  name                 = "${var.name}-tasky"
  image_tag_mutability = "MUTABLE"

  // Enable ECR scan-on-push for basic vuln scanning.
  image_scanning_configuration {
    scan_on_push = true
  }
}
