################################################################################
# GitHub Actions OIDC -> AWS role (no static AWS keys in GitHub)
################################################################################

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the repo"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo name (no org), e.g. wiz-exercise"
}

variable "enable_github_oidc" {
  type        = bool
  description = "Whether to create GitHub OIDC provider + IAM role for GitHub Actions"
  default     = true
}

# Creates an IAM Identity Provider for GitHub Actions (OIDC)
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Commonly used thumbprint for token.actions.githubusercontent.com
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role that GitHub Actions can assume
resource "aws_iam_role" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0

  name = "${var.name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          },
          StringLike = {
            # Only allow this repo's main branch to assume the role
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# For an interview sandbox, AdminAccess is acceptable and explainable.
# In production, you'd scope least privilege.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  count      = var.enable_github_oidc ? 1 : 0
  role       = aws_iam_role.github_actions[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_role_arn" {
  value       = var.enable_github_oidc ? aws_iam_role.github_actions[0].arn : null
  description = "Put this in GitHub repo secret AWS_ROLE_TO_ASSUME"
}
