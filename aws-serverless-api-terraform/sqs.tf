# Dead Letter Queue — receives messages that failed processing after max retries
resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${var.project_name}-notifications-dlq"
  message_retention_seconds = 1209600  # 14 days — long enough to investigate failures

  tags = { Project = var.project_name }
}

# Main queue — task notification events go here
resource "aws_sqs_queue" "notifications" {
  name                       = "${var.project_name}-notifications"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 86400   # 1 day
  receive_wait_time_seconds  = 20      # Long polling — reduces empty receive calls

  # If a message fails 3 times, send to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  tags = { Project = var.project_name }
}

# Alarm: alert when messages pile up in DLQ (something is broken)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in DLQ — investigate failed notifications"
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.notifications_dlq.name }
  tags       = { Project = var.project_name }
}
