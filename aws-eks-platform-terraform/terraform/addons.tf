# =============================================================================
# Kubernetes Add-ons and Controllers
# =============================================================================
# These components extend EKS with production capabilities:
# - Ingress (ALB Controller)
# - Auto-scaling (Cluster Autoscaler)
# - Storage (EBS CSI Driver)
# - Secrets (External Secrets Operator)
# - Monitoring (Metrics Server, Prometheus Stack)
# - GitOps (ArgoCD)
# =============================================================================

# =============================================================================
# AWS Load Balancer Controller
# =============================================================================
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1" # Updated to latest stable

  # Wait for resources to be ready
  wait    = true
  timeout = 600 # 10 minutes

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
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
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "replicaCount"
    value = "2"
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.main.id
  }

  set {
    name  = "podDisruptionBudget.maxUnavailable"
    value = "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "enableServiceMutatorWebhook"
    value = "true"
  }

  set {
    name  = "enableEndpointSlices"
    value = "true"
  }

  set {
    name  = "ingressClassConfig.default"
    value = "true"
  }

  depends_on = [
    aws_eks_node_group.main,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# Cluster Autoscaler
# =============================================================================
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.43.2" # Updated to latest

  wait    = true
  timeout = 600

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  # Production autoscaling parameters
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-delete"
    value = "10s"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-failure"
    value = "3m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "10m"
  }

  set {
    name  = "extraArgs.scale-down-utilization-threshold"
    value = "0.5"
  }

  set {
    name  = "extraArgs.max-node-provision-time"
    value = "15m"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  set {
    name  = "podDisruptionBudget.maxUnavailable"
    value = "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "300Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "500Mi"
  }

  set {
    name  = "nodeSelector.role"
    value = "system"
  }

  depends_on = [
    aws_eks_node_group.main,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# EBS CSI Driver (via EKS Add-on)
# =============================================================================
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.34.0-eksbuild.1" # Latest stable
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # Resolve conflicts by overwriting
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    controller = {
      extraVolumeTags = {
        "kubernetes.io/cluster/${local.cluster_name}" = "owned"
        Project                                       = var.project_name
        Environment                                   = var.environment
        ManagedBy                                     = "terraform"
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    }
    node = {
      tolerateAllTaints = true
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }
    storageClasses = [{
      name = "ebs-sc"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
      provisioner       = "ebs.csi.aws.com"
      volumeBindingMode = "WaitForFirstConsumer"
      parameters = {
        type       = "gp3"
        encrypted  = "true"
        kmsKeyId   = aws_kms_key.eks.arn
        throughput = "125"
        iops       = "3000"
      }
    }]
  })

  depends_on = [
    aws_eks_node_group.main,
    time_sleep.wait_for_eks
  ]

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# =============================================================================
# External Secrets Operator
# =============================================================================
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.5" # Updated to latest

  wait    = true
  timeout = 300

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets.arn
  }

  set {
    name  = "replicaCount"
    value = "2"
  }

  set {
    name  = "podDisruptionBudget.minAvailable"
    value = "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "nodeSelector.role"
    value = "system"
  }

  # Enable webhook for secret validation
  set {
    name  = "webhook.port"
    value = "9443"
  }

  set {
    name  = "certController.replicaCount"
    value = "2"
  }

  depends_on = [
    aws_eks_node_group.main,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# Metrics Server (Required for HPA)
# =============================================================================
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2" # Updated to latest

  wait    = true
  timeout = 300

  set {
    name  = "replicas"
    value = "2"
  }

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  set {
    name  = "args[1]"
    value = "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
  }

  set {
    name  = "args[2]"
    value = "--metric-resolution=15s"
  }

  set {
    name  = "podDisruptionBudget.minAvailable"
    value = "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "nodeSelector.role"
    value = "system"
  }

  depends_on = [
    aws_eks_node_group.main,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# ArgoCD (GitOps Controller)
# =============================================================================
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.3.4" # Updated to latest

  wait    = true
  timeout = 600

  values = [<<-YAML
    global:
      nodeSelector:
        role: system
      tolerations:
        - key: "spot"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      securityContext:
        runAsNonRoot: true
        runAsUser: 999

    # HA Configuration
    controller:
      replicas: 2
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi

    server:
      replicas: 2
      autoscaling:
        enabled: true
        minReplicas: 2
        maxReplicas: 5
        targetCPUUtilizationPercentage: 70
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
      service:
        type: ClusterIP
      ingress:
        enabled: false  # We'll use ALB ingress separately
      podDisruptionBudget:
        minAvailable: 1

    repoServer:
      replicas: 2
      autoscaling:
        enabled: true
        minReplicas: 2
        maxReplicas: 5
        targetCPUUtilizationPercentage: 70
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 200m
          memory: 512Mi
      podDisruptionBudget:
        minAvailable: 1

    applicationSet:
      replicas: 2
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi

    notifications:
      enabled: true
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi

    dex:
      enabled: false  # Use SSO via ALB instead

    redis:
      enabled: true
      architecture: standalone  # Single Redis for this project
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi

    configs:
      params:
        server.insecure: true  # TLS terminated at ALB
      cm:
        timeout.reconciliation: 180s
        resource.customizations: |
          apps/Deployment:
            health.lua: |
              hs = {}
              hs.status = "Progressing"
              hs.message = ""
              if obj.status ~= nil then
                if obj.status.conditions ~= nil then
                  for i, condition in ipairs(obj.status.conditions) do
                    if condition.type == "Available" and condition.status == "True" then
                      hs.status = "Healthy"
                      return hs
                    end
                  end
                end
              end
              return hs
      repositories: |
        - url: ${local.github_repo_url}
          type: git
          name: platform-repo
  YAML
  ]

  depends_on = [
    aws_eks_node_group.main,
    helm_release.alb_controller,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# Prometheus Stack (Monitoring)
# =============================================================================
resource "helm_release" "prometheus_stack" {
  name             = "prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "61.3.2"

  wait    = true
  timeout = 600

  values = [<<-YAML
    global:
      nodeSelector:
        role: system

    alertmanager:
      enabled: true
      replicas: 2
      podDisruptionBudget:
        minAvailable: 1

    prometheus:
      enabled: true
      replicas: 2
      podDisruptionBudget:
        minAvailable: 1
      prometheusSpec:
        retention: 7d
        retentionSize: 20GB
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 20Gi
              storageClassName: ebs-sc
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi

    grafana:
      enabled: true
      replicas: 2
      podDisruptionBudget:
        minAvailable: 1
      persistence:
        enabled: true
        size: 10Gi
        storageClassName: ebs-sc
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 200m
          memory: 512Mi
      adminPassword: admin  # CHANGE THIS IN PRODUCTION!
      ingress:
        enabled: false  # We'll use separate ALB ingress

    nodeExporter:
      enabled: true

    kubeStateMetrics:
      enabled: true

    prometheusOperator:
      replicas: 2
      podDisruptionBudget:
        minAvailable: 1
  YAML
  ]

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.ebs_csi,
    time_sleep.wait_for_eks
  ]
}

# =============================================================================
# Outputs for ArgoCD Access
# =============================================================================
output "argocd_admin_password" {
  description = "ArgoCD admin password (get with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = "admin" # CHANGE IN PRODUCTION!
  sensitive   = true
}
