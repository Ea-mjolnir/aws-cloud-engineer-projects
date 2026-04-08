output "alb_endpoint"    { value = "http://${aws_lb.main.dns_name}" }
output "ecr_repo_url"    { value = aws_ecr_repository.app.repository_url }
output "ecs_cluster"     { value = aws_ecs_cluster.main.name }
output "github_role_arn" { value = aws_iam_role.github_actions.arn }
output "dashboard_url"   {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-overview"
}
