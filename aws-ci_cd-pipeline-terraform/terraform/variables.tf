variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "cicd-pipeline"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "github_org" {
  type        = string
  description = "Your GitHub username or org"
}

variable "github_repo" {
  type    = string
  default = "aws-cicd-pipeline-terraform"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "dynamodb_table" {
  type    = string
  default = "cicd-tasks"
}
