variable "tasky_namespace" {
  type    = string
  default = "tasky"
}

variable "tasky_image_tag" {
  type        = string
  description = "Image tag to deploy from the Terraform-created ECR repo"
  default     = "latest"
}

resource "kubernetes_namespace" "tasky" {
  metadata {
    name = var.tasky_namespace
  }
}

resource "kubernetes_service_account" "tasky" {
  metadata {
    name      = "tasky-sa"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
}

# INTENTIONAL WEAKNESS (mirrors your YAML) — but now uniquely named to avoid collisions.
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

resource "kubernetes_secret" "tasky_env" {
  metadata {
    name      = "tasky-env"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }

  type = "Opaque"

  data = {
    MONGODB_URI = local.mongo_uri
  }
}

resource "kubernetes_deployment" "tasky" {
  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    labels    = { app = "tasky" }
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

          env_from {
            secret_ref {
              name = kubernetes_secret.tasky_env.metadata[0].name
            }
          }

          # INTENTIONAL WEAKNESS (mirrors your YAML)
          security_context {
            privileged = true
          }
        }
      }
    }
  }
}

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
