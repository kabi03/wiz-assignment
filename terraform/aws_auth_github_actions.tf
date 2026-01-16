// Map the GitHub Actions IAM role into aws-auth.

// Look up the GitHub Actions role created by OIDC.
data "aws_iam_role" "github_actions" {
  // This role is defined in terraform/github_oidc.tf.
  name = "${var.name}-github-actions"
}

// Read the current aws-auth ConfigMap.
data "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
}

locals {
  // Build a new mapRoles list that includes the GitHub Actions role.
  // Existing mapRoles list from aws-auth.
  existing_map_roles = try(
    yamldecode(lookup(data.kubernetes_config_map_v1.aws_auth.data, "mapRoles", "[]")),
    []
  )

  // Role mapping we want to add.
  github_actions_role_entry = {
    rolearn  = data.aws_iam_role.github_actions.arn
    username = "github-actions"
    groups   = ["system:masters"]
  }

  // Merge by removing any duplicate rolearn and appending ours.
  merged_map_roles = concat(
    [for r in local.existing_map_roles : r if try(r.rolearn, "") != data.aws_iam_role.github_actions.arn],
    [local.github_actions_role_entry]
  )

  // Preserve mapUsers/mapAccounts and update mapRoles.
  existing_data = data.kubernetes_config_map_v1.aws_auth.data

  new_data = merge(
    local.existing_data,
    {
      mapRoles = yamlencode(local.merged_map_roles)
    }
  )
}

// Write the updated aws-auth ConfigMap.
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = local.new_data
}
