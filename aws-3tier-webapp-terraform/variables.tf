variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "app3tier-webapp"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "db_password" {
  description = "RDS master password — pass via TF_VAR_db_password env var, never hardcode"
  type        = string
  sensitive   = true
}

variable "db_username" {
  type    = string
  default = "webapp_admin"
}
