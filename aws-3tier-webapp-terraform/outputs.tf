output "application_url" {
  description = "The public URL to access your web application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "rds_connection_string" {
  description = "Example connection string for your app"
  value       = "mysql://${var.db_username}:${var.db_password}@${aws_db_instance.main.endpoint}/appdb"
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the main VPC"
  value       = aws_vpc.main.id
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-overview"
}
