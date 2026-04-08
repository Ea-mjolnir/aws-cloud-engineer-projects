resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  alarm_description   = "Scale out when average CPU utilization exceeds 70% for 2 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 70
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.app.name }
  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
  tags = { Name = "${var.project_name}-high-cpu", Project = var.project_name }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  alarm_description   = "Scale in when average CPU utilization drops below 30% for 3 minutes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  threshold           = 30
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.app.name }
  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
  tags = { Name = "${var.project_name}-low-cpu", Project = var.project_name }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  alarm_description   = "ALB is returning too many 5xx errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 10
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  dimensions = { LoadBalancer = aws_lb.main.arn_suffix }
  treat_missing_data = "notBreaching"
  tags = { Name = "${var.project_name}-alb-5xx", Project = var.project_name }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title = "EC2 CPU Utilization (%)"
          region = var.aws_region
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name]]
          period = 60
          stat = "Average"
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          title = "ALB Request Count"
          region = var.aws_region
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]]
          period = 60
          stat = "Sum"
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          title = "ALB 5XX Error Count"
          region = var.aws_region
          metrics = [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]]
          period = 60
          stat = "Sum"
          view = "timeSeries"
        }
      }
    ]
  })
}
