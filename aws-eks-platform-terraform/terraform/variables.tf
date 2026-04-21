# =============================================================================
# Core Configuration
# =============================================================================
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be valid format (e.g., us-east-1, eu-west-2)."
  }
}

variable "project_name" {
  description = "Project name used for resource tagging and naming"
  type        = string
  default     = "eks-platform"

  validation {
    condition     = length(var.project_name) <= 20
    error_message = "Project name must be 20 characters or less for AWS resource name limits."
  }
}

variable "environment" {
  description = "Environment name (production, staging, dev)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "Environment must be production, staging, or dev."
  }
}

# =============================================================================
# Kubernetes Configuration
# =============================================================================
variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^1\\.(2[8-9]|3[0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.28+ and use standard EKS supported versions."
  }
}

# =============================================================================
# GitOps Configuration
# =============================================================================
variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "Ea-mjolnir"
}

variable "github_repo" {
  description = "GitHub repository name for GitOps"
  type        = string
  default     = "aws-eks-platform-terraform"

  validation {
    condition     = length(var.github_repo) > 0
    error_message = "GitHub repository name cannot be empty."
  }
}

variable "git_branch" {
  description = "Git branch to track for GitOps"
  type        = string
  default     = "main"
}

# =============================================================================
# Node Group Configuration
# =============================================================================
variable "node_groups" {
  description = "EKS managed node group configurations"
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
    disk_size         = optional(number, 50)
    ami_type          = optional(string, "AL2_x86_64")
    enable_monitoring = optional(bool, true)
    update_config = optional(object({
      max_unavailable_percentage = optional(number, 33)
    }))
  }))

  default = {
    system = {
      instance_types    = ["t3.medium"]
      capacity_type     = "ON_DEMAND"
      min_size          = 2
      max_size          = 4
      desired_size      = 2
      disk_size         = 50
      ami_type          = "AL2_x86_64"
      enable_monitoring = true
      labels = {
        role        = "system"
        managed-by  = "terraform"
        cost-center = "platform"
      }
      taints = []
      update_config = {
        max_unavailable_percentage = 33
      }
    }

    apps = {
      instance_types    = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
      capacity_type     = "SPOT"
      min_size          = 1
      max_size          = 10
      desired_size      = 2
      disk_size         = 100
      ami_type          = "AL2_x86_64"
      enable_monitoring = true
      labels = {
        role        = "apps"
        managed-by  = "terraform"
        cost-center = "platform"
        spot        = "true"
      }
      taints = [
        {
          key    = "spot"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
      update_config = {
        max_unavailable_percentage = 25
      }
    }
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : ng.capacity_type == "SPOT" || ng.capacity_type == "ON_DEMAND"
    ])
    error_message = "capacity_type must be either SPOT or ON_DEMAND."
  }

  validation {
    condition = alltrue([
      for ng in var.node_groups : ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size
    ])
    error_message = "Must satisfy: min_size <= desired_size <= max_size for all node groups."
  }
}

# =============================================================================
# Network Configuration
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be valid IPv4 CIDR notation."
  }
}

variable "availability_zones" {
  description = "List of availability zones (defaults to 3 AZs in region)"
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null || length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required for high availability."
  }
}

# =============================================================================
# Add-on Configuration
# =============================================================================
variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler add-on"
  type        = bool
  default     = true
}

variable "enable_external_secrets" {
  description = "Enable External Secrets Operator"
  type        = bool
  default     = true
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI Driver for persistent volumes"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable Metrics Server (required for HPA)"
  type        = bool
  default     = true
}

# =============================================================================
# Security Configuration
# =============================================================================
variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "EKS control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for log in var.cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log)
    ])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access cluster API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

variable "enable_public_endpoint" {
  description = "Enable public endpoint for EKS API (false = private only)"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for EKS API (VPC internal)"
  type        = bool
  default     = true
}

# =============================================================================
# Tags
# =============================================================================
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Locals (Derived values)
# =============================================================================
locals {
  # Dynamic AZ calculation - uses a default if not specified
  azs = var.availability_zones != null ? var.availability_zones : ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Common tags merged with additional tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )

  # Node group name prefix
  node_group_name_prefix = "${var.project_name}-${var.environment}"

  # Cluster name
  cluster_name = "${var.project_name}-${var.environment}-cluster"

  # IAM role name prefix
  iam_role_prefix = "${var.project_name}-${var.environment}"

  # GitHub URL for ArgoCD
  github_repo_url = "https://github.com/${var.github_org}/${var.github_repo}"
}

# =============================================================================
# Data Sources for Dynamic Values (Moved to vpc.tf and eks.tf)
# =============================================================================
# These are referenced in the files where they're actually used
