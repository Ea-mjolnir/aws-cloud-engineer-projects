variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "serverless-api"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "lambda_memory_mb" {
  description = "Memory allocated to Lambda functions"
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Max execution time per Lambda invocation"
  type        = number
  default     = 30
}

variable "api_throttle_rate_limit" {
  description = "Requests per second allowed through API Gateway"
  type        = number
  default     = 100
}

variable "api_throttle_burst_limit" {
  description = "Max concurrent requests allowed"
  type        = number
  default     = 200
}

variable "sqs_visibility_timeout" {
  description = "Seconds a message is hidden after being received"
  type        = number
  default     = 60
}

variable "dlq_max_receive_count" {
  description = "Times a message is retried before going to DLQ"
  type        = number
  default     = 3
}
