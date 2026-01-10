################################################################################
# Map GitHub Actions IAM role into EKS via aws-auth ConfigMap (CONFIG_MAP mode)
################################################################################

data "aws_iam_role" "github_actions" {
  name = "${var.name}-github-actions"
}

# Read the existing aws-auth ConfigMap
data "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
}

locals {
  # Existing mapRoles list (YAML -> list(object))
  existing_map_roles = try(
    yamldecode(lookup(data.kubernetes_config_map_v1.aws_auth.data, "mapRoles", "[]")),
    []
  )

  # The entry we want to ensure exists
  github_actions_role_entry = {
    rolearn  = data.aws_iam_role.github_actions.arn
    username = "github-actions"
    groups   = ["system:masters"]
  }

  # Remove any existing entry for this rolearn, then add ours
  merged_map_roles = concat(
    [for r in local.existing_map_roles : r if try(r.rolearn, "") != data.aws_iam_role.github_actions.arn],
    [local.github_actions_role_entry]
  )

  # Preserve other keys (mapUsers/mapAccounts) exactly as-is
  existing_data = data.kubernetes_config_map_v1.aws_auth.data

  new_data = merge(
    local.existing_data,
    {
      mapRoles = yamlencode(local.merged_map_roles)
    }
  )
}

# Write back aws-auth with the merged roles
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = local.new_data
}
