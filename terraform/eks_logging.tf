# terraform/eks_logging.tf

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  # This is the default log group name EKS uses for control plane logs
  name = "/aws/eks/${var.name}/cluster"

  # Keep costs low in the sandbox
  retention_in_days = 7
}
