resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "Task Management API"

  endpoint_configuration { types = ["REGIONAL"] }

  tags = { Project = var.project_name }
}

# Cognito authorizer - configured to accept client_id instead of aud
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}

# /tasks resource
resource "aws_api_gateway_resource" "tasks" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "tasks"
}

# /tasks/{taskId}
resource "aws_api_gateway_resource" "task" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.tasks.id
  path_part   = "{taskId}"
}

# /tasks/{taskId}/upload-url
resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.task.id
  path_part   = "upload-url"
}

# Define routes with static keys
locals {
  api_routes = {
    "POST_tasks" = {
      resource_id = aws_api_gateway_resource.tasks.id
      http_method = "POST"
    }
    "GET_tasks" = {
      resource_id = aws_api_gateway_resource.tasks.id
      http_method = "GET"
    }
    "GET_task" = {
      resource_id = aws_api_gateway_resource.task.id
      http_method = "GET"
    }
    "PUT_task" = {
      resource_id = aws_api_gateway_resource.task.id
      http_method = "PUT"
    }
    "DELETE_task" = {
      resource_id = aws_api_gateway_resource.task.id
      http_method = "DELETE"
    }
    "GET_upload_url" = {
      resource_id = aws_api_gateway_resource.upload_url.id
      http_method = "GET"
    }
  }
}

resource "aws_api_gateway_method" "routes" {
  for_each      = local.api_routes
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value.resource_id
  http_method   = each.value.http_method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "routes" {
  for_each                = aws_api_gateway_method.routes
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_integration.routes]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Account Settings (needed for CloudWatch logs)
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

# Stage with logging
resource "aws_api_gateway_stage" "production" {
  depends_on = [aws_api_gateway_account.main]

  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.environment

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
      responseLatency    = "$context.responseTime"
    })
  }

  tags = { Project = var.project_name }
}

# Lambda permission
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
