# =============================================================================
# Terraform Outputs - EKS Platform
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster Information
# -----------------------------------------------------------------------------
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority" {
  description = "Cluster CA certificate (base64 encoded)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# -----------------------------------------------------------------------------
# Region & Account
# -----------------------------------------------------------------------------
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# VPC & Networking
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where EKS nodes run)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB/NAT gateways)"
  value       = aws_subnet.public[*].id
}

# -----------------------------------------------------------------------------
# IAM & IRSA
# -----------------------------------------------------------------------------
output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions CI/CD"
  value       = aws_iam_role.github_actions.arn
}

output "task_api_role_arn" {
  description = "IAM role ARN for Task API service account (IRSA)"
  value       = aws_iam_role.task_api.arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI Driver"
  value       = aws_iam_role.ebs_csi.arn
}

# -----------------------------------------------------------------------------
# Node Groups
# -----------------------------------------------------------------------------
output "node_groups" {
  description = "Node group information"
  value = {
    for k, v in aws_eks_node_group.main : k => {
      name           = v.node_group_name
      capacity_type  = v.capacity_type
      instance_types = v.instance_types
      scaling_config = v.scaling_config[0]
    }
  }
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------
output "kms_key_arn" {
  description = "KMS key ARN for envelope encryption"
  value       = aws_kms_key.eks.arn
}

output "kms_key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.eks.key_id
}

# -----------------------------------------------------------------------------
# Add-on Status
# -----------------------------------------------------------------------------
output "addons" {
  description = "EKS add-ons status"
  value = {
    ebs_csi = {
      name    = aws_eks_addon.ebs_csi.addon_name
      version = aws_eks_addon.ebs_csi.addon_version
    }
  }
}

output "helm_releases" {
  description = "Helm releases installed via Terraform"
  value = {
    alb_controller = {
      name    = helm_release.alb_controller.name
      version = helm_release.alb_controller.version
    }
    cluster_autoscaler = {
      name    = helm_release.cluster_autoscaler.name
      version = helm_release.cluster_autoscaler.version
    }
    external_secrets = {
      name    = helm_release.external_secrets.name
      version = helm_release.external_secrets.version
    }
    argocd = {
      name    = helm_release.argocd.name
      version = helm_release.argocd.version
    }
  }
}

# -----------------------------------------------------------------------------
# Access Commands
# -----------------------------------------------------------------------------
output "kubeconfig_command" {
  description = "Command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region} --alias ${aws_eks_cluster.main.name}"
}

output "argocd_password_command" {
  description = "Command to get ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Command to access ArgoCD UI locally"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "grafana_port_forward_command" {
  description = "Command to access Grafana UI locally"
  value       = "kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80"
}

output "task_api_port_forward_command" {
  description = "Command to access Task API locally"
  value       = "kubectl port-forward svc/task-api -n production 8081:80"
}

# -----------------------------------------------------------------------------
# ECR Information
# -----------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "ECR repository URL for Task API"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project_name}/task-api"
}

output "ecr_login_command" {
  description = "Command to login to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# -----------------------------------------------------------------------------
# GitHub Actions Secrets Reference
# -----------------------------------------------------------------------------
output "github_secrets_reference" {
  description = "Values to set as GitHub Secrets for CI/CD"
  value = {
    AWS_REGION        = var.aws_region
    AWS_ROLE_ARN      = aws_iam_role.github_actions.arn
    EKS_CLUSTER       = aws_eks_cluster.main.name
    ECR_REGISTRY      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    TASK_API_ROLE_ARN = aws_iam_role.task_api.arn
  }
  sensitive = true
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
output "summary" {
  description = "Platform summary with all key information"
  value       = <<-EOT
    
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                           🎉 EKS PLATFORM READY 🎉                             ║
    ╠═══════════════════════════════════════════════════════════════════════════════╣
    ║                                                                               ║
    ║  Cluster:         ${aws_eks_cluster.main.name} (${aws_eks_cluster.main.version})
    ║  Region:          ${var.aws_region}                                           
    ║  Account:         ${data.aws_caller_identity.current.account_id}              
    ║  VPC:             ${aws_vpc.main.id} (${aws_vpc.main.cidr_block})             
    ║                                                                               ║
    ║  Node Groups:                                                                 
    %{for k, v in var.node_groups~}
    ║    - ${k}: ${v.min_size}-${v.max_size} nodes (${v.capacity_type})              
    %{endfor~}
    ║                                                                               ║
    ║  OIDC Provider:   ${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}
    ║                                                                               ║
    ║  🔐 GitHub Secrets Required:                                                   ║
    ║    AWS_ROLE_ARN = ${aws_iam_role.github_actions.arn}
    ║                                                                               ║
    ║  📋 Next Steps:                                                               ║
    ║    1. Update kubeconfig:                                                      ║
    ║       aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}
    ║                                                                               ║
    ║    2. Bootstrap platform:                                                     ║
    ║       ./scripts/bootstrap.sh                                                  ║
    ║                                                                               ║
    ║    3. Get ArgoCD password:                                                    ║
    ║       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
    ║                                                                               ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
    
  EOT
}
