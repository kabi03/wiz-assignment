// EKS control plane log group configuration.

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  // Default log group name used by EKS.
  name = "/aws/eks/${var.name}/cluster"

  // Short retention to keep costs low in the lab.
  retention_in_days = 7
}
