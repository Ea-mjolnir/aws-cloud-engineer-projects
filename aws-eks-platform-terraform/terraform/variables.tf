variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "eks-platform"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "github_org" {
  type    = string
  default = "Ea-mjolnir"
}

variable "github_repo" {
  type    = string
  default = "aws-cloud-engineer-projects"
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "node_groups" {
  description = "EKS node groups - single t3.micro for Free Tier"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    disk_size = optional(number, 20)
    ami_type  = optional(string, "AL2_x86_64")
    update_config = optional(object({
      max_unavailable_percentage = optional(number, 33)
    }))
  }))

  default = {
    system = {
      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 20
      ami_type       = "AL2_x86_64"
      labels = {
        role       = "system"
        managed-by = "terraform"
      }
      taints = []
      update_config = {
        max_unavailable_percentage = 33
      }
    }
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = null
}

variable "enable_cluster_autoscaler" {
  type    = bool
  default = false
}

variable "enable_external_secrets" {
  type    = bool
  default = false
}

variable "enable_aws_load_balancer_controller" {
  type    = bool
  default = false
}

variable "enable_ebs_csi_driver" {
  type    = bool
  default = false
}

variable "enable_metrics_server" {
  type    = bool
  default = false
}

variable "enable_irsa" {
  type    = bool
  default = true
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_public_endpoint" {
  type    = bool
  default = true
}

variable "enable_private_endpoint" {
  type    = bool
  default = true
}

variable "additional_tags" {
  type    = map(string)
  default = {}
}

locals {
  azs = var.availability_zones != null ? var.availability_zones : ["us-east-1a", "us-east-1b", "us-east-1c"]

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )

  node_group_name_prefix = "${var.project_name}-${var.environment}"
  cluster_name           = "${var.project_name}-${var.environment}-cluster"
  iam_role_prefix        = "${var.project_name}-${var.environment}"
  github_repo_url        = "https://github.com/${var.github_org}/${var.github_repo}"
}
