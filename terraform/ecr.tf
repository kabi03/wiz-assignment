resource "aws_ecr_repository" "app" {
  name                 = "${var.name}-tasky"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # preventative-ish control: enables scanning on push
  }
}
