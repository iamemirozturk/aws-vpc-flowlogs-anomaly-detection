output "sns_topic_arn" {
  description = "SNS alert topic ARN."
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_name" {
  description = "Detector Lambda function name."
  value       = aws_lambda_function.detector.function_name
}

output "lambda_function_arn" {
  description = "Detector Lambda function ARN."
  value       = aws_lambda_function.detector.arn
}

output "dlq_url" {
  description = "EventBridge target dead-letter queue URL."
  value       = aws_sqs_queue.detector_dlq.url
}

output "detection_state_table_name" {
  description = "DynamoDB idempotency table name."
  value       = aws_dynamodb_table.detection_state.name
}

output "alerts_kms_key_arn" {
  description = "KMS key protecting alerting and detector state."
  value       = aws_kms_key.alerts.arn
}
