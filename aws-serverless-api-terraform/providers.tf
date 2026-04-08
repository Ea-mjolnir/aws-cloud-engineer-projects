terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.7"
}

provider "aws" {
  region = var.aws_region
}

# WAF for API Gateway must be us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
