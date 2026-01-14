variable "tasky_namespace" {
  type    = string
  default = "tasky"
}

variable "tasky_image_tag" {
  type        = string
  description = "Image tag to deploy from the Terraform-created ECR repo"
  default     = "latest"
}

// Namespace for the Tasky app resources.
resource "kubernetes_namespace" "tasky" {
  metadata {
    name = var.tasky_namespace
  }
}

// Service account used by the Tasky deployment.
resource "kubernetes_service_account" "tasky" {
  metadata {
    name      = "tasky-sa"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
}

// Grant cluster-admin to the app service account for the lab.
resource "kubernetes_cluster_role_binding" "tasky_cluster_admin" {
  metadata {
    name = "${var.name}-tasky-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tasky.metadata[0].name
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
}

// Secret holding app environment variables.
resource "kubernetes_secret" "tasky_env" {
  metadata {
    name      = "tasky-env"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }

  type = "Opaque"

  // Provide the Mongo connection string to the app.
  data = {
    MONGODB_URI = local.mongo_uri
  }
}

// Tasky application deployment.
resource "kubernetes_deployment" "tasky" {
  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    labels    = { app = "tasky" }
  }

  // Let CI control the image tag and ignore drift in Terraform.
  lifecycle {
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image
    ]
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "tasky" }
    }

    template {
      metadata {
        labels = { app = "tasky" }
      }

      spec {
        service_account_name = kubernetes_service_account.tasky.metadata[0].name

        container {
          name  = "tasky"
          image = "${aws_ecr_repository.app.repository_url}:${var.tasky_image_tag}"

          port {
            container_port = 8080
          }

          // Inject secret values as environment variables.
          env_from {
            secret_ref {
              name = kubernetes_secret.tasky_env.metadata[0].name
            }
          }

          // Run the container as privileged for the lab.
          security_context {
            privileged = true
          }
        }
      }
    }
  }
}

// ClusterIP service to expose the Tasky pods.
resource "kubernetes_service" "tasky" {
  metadata {
    name      = "tasky-svc"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    labels    = { app = "tasky" }
  }

  spec {
    selector = { app = "tasky" }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

// Ingress that triggers ALB provisioning.
resource "kubernetes_ingress_v1" "tasky" {
  metadata {
    name      = "tasky-ingress"
    namespace = kubernetes_namespace.tasky.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.tasky.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
