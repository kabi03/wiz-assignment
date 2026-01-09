variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file used by Terraform Kubernetes/Helm providers"
  default     = "~/.kube/config"
}

variable "kube_context" {
  type        = string
  description = "Optional kubeconfig context name to use (leave empty to use current-context)"
  default     = ""
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context != "" ? var.kube_context : null
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context != "" ? var.kube_context : null
  }
}
