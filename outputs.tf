output "central_log_bucket_name" {
  description = "Central S3 bucket receiving VPC Flow Logs."
  value       = module.central_logging.log_bucket_name
}

output "central_log_bucket_arn" {
  description = "ARN supplied as central_log_bucket_arn to every spoke deployment."
  value       = module.central_logging.log_bucket_arn
}

output "glue_database_name" {
  description = "Glue Data Catalog database queried by Athena."
  value       = module.central_logging.glue_database_name
}

output "glue_table_name" {
  description = "Partition-projected Glue table queried by the detector."
  value       = module.central_logging.glue_table_name
}

output "athena_workgroup_name" {
  description = "Athena workgroup used for Flow Log queries."
  value       = module.central_logging.athena_workgroup_name
}

output "athena_results_bucket_name" {
  description = "S3 bucket holding Athena query results."
  value       = module.central_logging.athena_results_bucket_name
}

output "sns_alert_topic_arn" {
  description = "SNS alert topic ARN."
  value       = module.detection_engine.sns_topic_arn
}

output "lambda_function_name" {
  description = "Scheduled detector Lambda function name."
  value       = module.detection_engine.lambda_function_name
}

output "detector_dlq_url" {
  description = "SQS dead-letter queue URL for failed detector invocations and EventBridge deliveries."
  value       = module.detection_engine.dlq_url
}

output "flow_logs_kms_key_arn" {
  description = "KMS key protecting the central logs and Athena results."
  value       = module.central_logging.kms_key_arn
}
