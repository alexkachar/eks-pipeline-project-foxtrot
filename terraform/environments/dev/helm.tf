resource "kubernetes_namespace" "external_secrets" {
  count = var.enable_cluster_addons ? 1 : 0

  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_namespace" "argocd" {
  count = var.enable_cluster_addons ? 1 : 0

  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_cluster_addons ? 1 : 0

  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "todo_app" {
  count = var.enable_cluster_addons ? 1 : 0

  metadata {
    name = "todo-app"
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_cluster_addons ? 1 : 0

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
  count = var.enable_cluster_addons ? 1 : 0

  name       = "external-secrets"
  namespace  = "external-secrets"
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

  depends_on = [kubernetes_namespace.external_secrets]
}

resource "terraform_data" "aws_ssm_secret_store" {
  count = var.enable_cluster_addons ? 1 : 0

  depends_on = [helm_release.external_secrets]

  input = yamlencode({
    apiVersion = "external-secrets.io/v1"
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

  provisioner "local-exec" {
    command = <<-EOT
      cat <<'YAML' | kubectl apply -f -
      ${self.input}
      YAML
    EOT
  }
}

resource "helm_release" "argocd" {
  count = var.enable_cluster_addons ? 1 : 0

  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  values = [yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}

resource "helm_release" "loki" {
  count = var.enable_cluster_addons ? 1 : 0

  name       = "loki"
  namespace  = "monitoring"
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
        enabled = false
      }
      extraVolumes = [{
        name     = "loki-data"
        emptyDir = {}
      }]
      extraVolumeMounts = [{
        name      = "loki-data"
        mountPath = "/var/loki"
      }]
    }
    chunksCache = {
      enabled = false
    }
    resultsCache = {
      enabled = false
    }
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }
  })]

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "promtail" {
  count = var.enable_cluster_addons ? 1 : 0

  name       = "promtail"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"

  values = [yamlencode({
    config = {
      clients = [{
        url = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
      }]
    }
  })]

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_cluster_addons ? 1 : 0

  name       = "kube-prometheus-stack"
  namespace  = "monitoring"
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

  depends_on = [kubernetes_namespace.monitoring]
}

resource "terraform_data" "todo_app" {
  count = var.enable_cluster_addons ? 1 : 0

  depends_on = [
    helm_release.argocd,
    helm_release.aws_load_balancer_controller,
    terraform_data.aws_ssm_secret_store,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    helm_release.promtail
  ]

  input = yamlencode({
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

  provisioner "local-exec" {
    command = <<-EOT
      cat <<'YAML' | kubectl apply -f -
      ${self.input}
      YAML
    EOT
  }
}
