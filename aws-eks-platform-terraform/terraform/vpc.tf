# =============================================================================
# Data Sources
# =============================================================================
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# =============================================================================
# Local Variables (VPC-specific only)
# =============================================================================
locals {
  # Override AZs with actual available AZs if not specified in variables
  vpc_azs = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)

  # Calculate subnet CIDRs dynamically
  private_cidrs = [
    cidrsubnet(var.vpc_cidr, 3, 0),
    cidrsubnet(var.vpc_cidr, 3, 1),
    cidrsubnet(var.vpc_cidr, 3, 2)
  ]

  public_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 96),
    cidrsubnet(var.vpc_cidr, 8, 97),
    cidrsubnet(var.vpc_cidr, 8, 98)
  ]
}

# =============================================================================
# VPC
# =============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    {
      Name                                          = "${var.project_name}-${var.environment}-vpc"
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    },
    local.common_tags
  )
}

# =============================================================================
# Subnets
# =============================================================================
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.vpc_azs[count.index]

  tags = merge(
    {
      Name                                          = "${var.project_name}-private-${local.vpc_azs[count.index]}"
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb"             = "1"
      "karpenter.sh/discovery"                      = local.cluster_name
    },
    local.common_tags
  )
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.vpc_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name                                          = "${var.project_name}-public-${local.vpc_azs[count.index]}"
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/elb"                      = "1"
    },
    local.common_tags
  )
}

# =============================================================================
# Internet Gateway
# =============================================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    { Name = "${var.project_name}-${var.environment}-igw" },
    local.common_tags
  )
}

# =============================================================================
# NAT Gateways (One per AZ)
# =============================================================================
resource "aws_eip" "nat" {
  count  = 3
  domain = "vpc"

  tags = merge(
    { Name = "${var.project_name}-nat-eip-${count.index + 1}" },
    local.common_tags
  )
}

resource "aws_nat_gateway" "main" {
  count         = 3
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(
    { Name = "${var.project_name}-nat-${count.index + 1}" },
    local.common_tags
  )
}

# =============================================================================
# Route Tables
# =============================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    { Name = "${var.project_name}-public-rt" },
    local.common_tags
  )
}

resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    { Name = "${var.project_name}-private-rt-${count.index + 1}" },
    local.common_tags
  )
}

# =============================================================================
# Route Table Associations
# =============================================================================
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# VPC Endpoints for ECR (to reduce NAT costs)
# =============================================================================
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS from VPC"
  }

  tags = merge(
    { Name = "${var.project_name}-vpc-endpoints-sg" },
    local.common_tags
  )
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    { Name = "${var.project_name}-ecr-api-endpoint" },
    local.common_tags
  )
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    { Name = "${var.project_name}-ecr-dkr-endpoint" },
    local.common_tags
  )
}

resource "aws_vpc_endpoint" "sts" {
  count = var.environment == "production" ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    { Name = "${var.project_name}-sts-endpoint" },
    local.common_tags
  )
}
