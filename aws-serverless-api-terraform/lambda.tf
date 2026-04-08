# Package Lambda code into zip files
data "archive_file" "crud" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/tasks_crud"
  output_path = "${path.module}/lambda/crud.zip"
}

data "archive_file" "notification" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/tasks_notification"
  output_path = "${path.module}/lambda/notification.zip"
}

# ─── CRUD Lambda ──────────────────────────────────────────────────────────────
resource "aws_lambda_function" "crud" {
  function_name    = "${var.project_name}-tasks-crud"
  filename         = data.archive_file.crud.output_path
  source_code_hash = data.archive_file.crud.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"
  role             = aws_iam_role.lambda_crud.arn
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds

  # X-Ray active tracing
  tracing_config { mode = "Active" }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.tasks.name
      S3_BUCKET      = aws_s3_bucket.attachments.id
      SQS_QUEUE_URL  = aws_sqs_queue.notifications.url
      ENVIRONMENT    = var.environment
      LOG_LEVEL      = "INFO"
    }
  }

  # Structured logging to CloudWatch
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_crud.name
  }

  tags = { Project = var.project_name }

  depends_on = [aws_iam_role_policy.lambda_crud]
}

# ─── Notification Lambda ──────────────────────────────────────────────────────
resource "aws_lambda_function" "notification" {
  function_name    = "${var.project_name}-notifications"
  filename         = data.archive_file.notification.output_path
  source_code_hash = data.archive_file.notification.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"
  role             = aws_iam_role.lambda_notification.arn
  memory_size      = 128
  timeout          = var.sqs_visibility_timeout

  tracing_config { mode = "Active" }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_notification.name
  }

  tags = { Project = var.project_name }
}

# SQS → Lambda trigger
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.notifications.arn
  function_name                      = aws_lambda_function.notification.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5   # Wait up to 5s to batch messages

  # If the batch fails, don't discard — send individual failures to DLQ
  function_response_types = ["ReportBatchItemFailures"]
}
