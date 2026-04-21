# =============================================================================
# Cluster IAM Role
# =============================================================================
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_logging" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# =============================================================================
# EKS Cluster
# =============================================================================
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = var.enable_private_endpoint
    endpoint_public_access  = var.enable_public_endpoint
    public_access_cidrs     = var.allowed_cidr_blocks
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.cluster_log_types

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
    ip_family         = "ipv4"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_logging
  ]

  tags = merge(
    { Name = local.cluster_name },
    local.common_tags
  )
}

# =============================================================================
# Cluster Security Group
# =============================================================================
resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    { Name = "${local.cluster_name}-cluster-sg" },
    local.common_tags
  )
}

resource "aws_security_group_rule" "cluster_ingress_nodes" {
  description              = "Allow nodes to communicate with cluster API"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# =============================================================================
# KMS Key for Secrets Encryption
# =============================================================================
resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption key for ${local.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    { Name = "${local.cluster_name}-eks-key" },
    local.common_tags
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.cluster_name}-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

# =============================================================================
# Node Group IAM Role
# =============================================================================
resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# =============================================================================
# Node Security Group
# =============================================================================
resource "aws_security_group" "node" {
  name        = "${local.cluster_name}-node-sg"
  description = "EKS node security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow cluster to communicate with nodes"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  ingress {
    description = "Allow nodes to communicate with each other"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name                                          = "${local.cluster_name}-node-sg"
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    },
    local.common_tags
  )
}

# =============================================================================
# Managed Node Groups
# =============================================================================
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.node_group_name_prefix}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type

  ami_type        = lookup(each.value, "ami_type", "AL2_x86_64")
  disk_size       = lookup(each.value, "disk_size", 50)
  release_version = null

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable_percentage = lookup(each.value.update_config, "max_unavailable_percentage", 33)
  }

  labels = merge(
    each.value.labels,
    {
      "eks.amazonaws.com/nodegroup"    = "${local.node_group_name_prefix}-${each.key}"
      "eks.amazonaws.com/capacityType" = each.value.capacity_type
      "node.kubernetes.io/lifecycle"   = lower(each.value.capacity_type)
    }
  )

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      release_version
    ]
    create_before_destroy = true
  }

  tags = merge(
    {
      "k8s.io/cluster-autoscaler/enabled"                                            = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}"                              = "owned"
      "k8s.io/cluster-autoscaler/node-template/label/eks.amazonaws.com/capacityType" = each.value.capacity_type
    },
    local.common_tags
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policies,
    aws_security_group.node
  ]
}

# =============================================================================
# OIDC Provider (Required for IRSA)
# =============================================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(
    { Name = "${local.cluster_name}-oidc-provider" },
    local.common_tags
  )
}

# =============================================================================
# aws-auth ConfigMap
# =============================================================================
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.node.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }

  force = true

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}

# =============================================================================
# Time Sleep (Race Condition Prevention)
# =============================================================================
resource "time_sleep" "wait_for_eks" {
  depends_on      = [aws_eks_cluster.main]
  create_duration = "30s"
}
