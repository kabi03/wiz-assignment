// Path to the kubeconfig used by Terraform providers.
variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file used by Terraform Kubernetes/Helm providers"
  default     = "~/.kube/config"
}

// Optional kubeconfig context override.
variable "kube_context" {
  type        = string
  description = "Optional kubeconfig context name to use (leave empty to use current-context)"
  default     = ""
}

// Use the local kubeconfig for Kubernetes provider access.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  // Use the provided context if set, otherwise current-context.
  config_context = var.kube_context != "" ? var.kube_context : null
}

// Use the same kubeconfig for Helm releases.
provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    // Match the same context as the Kubernetes provider.
    config_context = var.kube_context != "" ? var.kube_context : null
  }
}
