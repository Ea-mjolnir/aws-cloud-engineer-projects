resource "aws_cloudwatch_log_group" "lambda_crud" {
  name              = "/aws/lambda/${var.project_name}-tasks-crud"
  retention_in_days = 30
  tags              = { Project = var.project_name }
}

resource "aws_cloudwatch_log_group" "lambda_notification" {
  name              = "/aws/lambda/${var.project_name}-notifications"
  retention_in_days = 30
  tags              = { Project = var.project_name }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 30
  tags              = { Project = var.project_name }
}

resource "aws_cloudwatch_log_metric_filter" "lambda_errors" {
  name           = "${var.project_name}-lambda-errors"
  pattern        = "{ $.level = \"ERROR\" }"
  log_group_name = aws_cloudwatch_log_group.lambda_crud.name

  metric_transformation {
    name      = "LambdaErrorCount"
    namespace = "${var.project_name}/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LambdaErrorCount"
  namespace           = "${var.project_name}/Application"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda error rate is elevated"
  treat_missing_data  = "notBreaching"
  tags                = { Project = var.project_name }
}

resource "aws_cloudwatch_query_definition" "errors" {
  name = "${var.project_name}/errors"

  log_group_names = [aws_cloudwatch_log_group.lambda_crud.name]

  query_string = <<-QUERY
    fields @timestamp, action, userId, taskId, error
    | filter ispresent(error)
    | sort @timestamp desc
    | limit 50
  QUERY
}
