terraform {
  backend "s3" {
    bucket         = "eks-platform-tfstate-288528696055"
    key            = "production/eks-platform-production-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks-production"
  }
}
