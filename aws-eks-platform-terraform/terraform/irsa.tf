# =============================================================================
# IRSA (IAM Roles for Service Accounts)
# =============================================================================

locals {
  oidc_provider     = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  aws_account_id    = data.aws_caller_identity.current.account_id
}

# =============================================================================
# IRSA Assume Role Policy Helper
# =============================================================================
locals {
  irsa_assume_policy = { for k, v in {
    alb_controller     = { ns = "kube-system", sa = "aws-load-balancer-controller" }
    cluster_autoscaler = { ns = "kube-system", sa = "cluster-autoscaler" }
    ebs_csi            = { ns = "kube-system", sa = "ebs-csi-controller-sa" }
    external_secrets   = { ns = "external-secrets", sa = "external-secrets" }
    external_dns       = { ns = "kube-system", sa = "external-dns" }
    cert_manager       = { ns = "cert-manager", sa = "cert-manager" }
    task_api           = { ns = "production", sa = "task-api" }
    argocd             = { ns = "argocd", sa = "argocd-application-controller" }
    } : k => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = local.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider}:sub" = "system:serviceaccount:${v.ns}:${v.sa}"
          }
        }
      }]
  }) }
}

# =============================================================================
# AWS Load Balancer Controller Role
# =============================================================================
resource "aws_iam_role" "alb_controller" {
  name               = "${local.iam_role_prefix}-alb-controller"
  assume_role_policy = local.irsa_assume_policy["alb_controller"]
  tags               = local.common_tags
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags", "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeRules", "elasticloadbalancing:DescribeTags"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyListener", "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "alb-controller-policy"
  role   = aws_iam_role.alb_controller.id
  policy = data.aws_iam_policy_document.alb_controller.json
}

# =============================================================================
# Cluster Autoscaler Role
# =============================================================================
resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.iam_role_prefix}-cluster-autoscaler"
  assume_role_policy = local.irsa_assume_policy["cluster_autoscaler"]
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# EBS CSI Driver Role
# =============================================================================
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.iam_role_prefix}-ebs-csi"
  assume_role_policy = local.irsa_assume_policy["ebs_csi"]
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# =============================================================================
# External Secrets Operator Role
# =============================================================================
resource "aws_iam_role" "external_secrets" {
  name               = "${local.iam_role_prefix}-external-secrets"
  assume_role_policy = local.irsa_assume_policy["external_secrets"]
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ]
      Resource = [
        "arn:aws:secretsmanager:${var.aws_region}:${local.aws_account_id}:secret:${var.project_name}/*",
        "arn:aws:secretsmanager:${var.aws_region}:${local.aws_account_id}:secret:eks-platform/*"
      ]
    }]
  })
}

# =============================================================================
# Task API Role (Application-specific)
# =============================================================================
resource "aws_iam_role" "task_api" {
  name               = "${local.iam_role_prefix}-task-api"
  assume_role_policy = local.irsa_assume_policy["task_api"]
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "task_api" {
  name = "task-api-policy"
  role = aws_iam_role.task_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.aws_account_id}:table/${var.project_name}-tasks*"
      }
    ]
  })
}

# =============================================================================
# GitHub Actions Role (CI/CD)
# =============================================================================
resource "aws_iam_role" "github_actions" {
  name = "${local.iam_role_prefix}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = aws_eks_cluster.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# GitHub OIDC Provider
# =============================================================================
resource "aws_iam_openid_connect_provider" "github_actions_oidc" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(
    { Name = "github-actions-oidc-provider" },
    local.common_tags
  )
}
