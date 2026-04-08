output "api_endpoint" {
  description = "Base URL for all API calls"
  value       = "${aws_api_gateway_stage.production.invoke_url}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.api.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "xray_console" {
  description = "View distributed traces"
  value       = "https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/traces"
}
