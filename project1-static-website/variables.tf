variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Your domain name (e.g. myportfolio.com)"
  type        = string
  default     = "myportfolio.com"
}

variable "project_name" {
  description = "Project identifier for naming/tagging"
  type        = string
  default     = "aws-portfolio"
}
