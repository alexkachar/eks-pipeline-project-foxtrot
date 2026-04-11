resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "todo_app" {
  metadata {
    name = "todo-app"
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.alb_controller_role_arn
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.eso_role_arn
  }
}

resource "kubectl_manifest" "aws_ssm_secret_store" {
  depends_on = [helm_release.external_secrets]
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-ssm"
    }
    spec = {
      provider = {
        aws = {
          service = "ParameterStore"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  values = [yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })]
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type = "filesystem"
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index = {
            prefix = "loki_index_"
            period = "24h"
          }
        }]
      }
    }
    singleBinary = {
      replicas = 1
      persistence = {
        enabled = true
        size    = "10Gi"
      }
    }
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }
  })]
}

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"

  values = [yamlencode({
    config = {
      clients = [{
        url = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
      }]
    }
  })]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"

  values = [yamlencode({
    grafana = {
      persistence = {
        enabled = false
      }
      sidecar = {
        dashboards = {
          enabled = true
          label   = "grafana_dashboard"
        }
      }
      additionalDataSources = [{
        name      = "Loki"
        uid       = "loki"
        type      = "loki"
        access    = "proxy"
        url       = "http://loki-gateway.monitoring.svc.cluster.local"
        isDefault = false
      }]
    }
    prometheus = {
      prometheusSpec = {
        retention = "6h"
      }
    }
  })]
}

resource "kubectl_manifest" "todo_app" {
  depends_on = [
    helm_release.argocd,
    helm_release.aws_load_balancer_controller,
    kubectl_manifest.aws_ssm_secret_store,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    helm_release.promtail
  ]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "todo-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_repo}.git"
        targetRevision = "main"
        path           = "k8s/helm/todo-app"
        helm = {
          valueFiles = ["values.yaml", "image-overrides.yaml"]
          parameters = [
            { name = "frontend.image.repository", value = module.ecr.repository_urls["todo-app-frontend"] },
            { name = "backend.image.repository", value = module.ecr.repository_urls["todo-app-backend"] },
            { name = "ingress.certificateArn", value = data.aws_acm_certificate.wildcard.arn },
            { name = "ingress.host", value = var.app_host },
            { name = "monitoringIngress.host", value = var.monitoring_host }
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "todo-app"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })
}
