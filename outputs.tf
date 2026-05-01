# ---------------------------------------------------------------------------
# Root Outputs
# ---------------------------------------------------------------------------

output "central_log_bucket_name" {
  description = "Name of the central S3 bucket receiving VPC Flow Logs."
  value       = module.central_logging.log_bucket_name
}

output "central_log_bucket_arn" {
  description = "ARN of the central S3 bucket."
  value       = module.central_logging.log_bucket_arn
}

output "glue_database_name" {
  description = "Name of the AWS Glue database for flow log tables."
  value       = module.central_logging.glue_database_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup used for flow log queries."
  value       = module.central_logging.athena_workgroup_name
}

output "athena_results_bucket_name" {
  description = "S3 bucket where Athena query results are stored."
  value       = module.central_logging.athena_results_bucket_name
}

output "sns_alert_topic_arn" {
  description = "ARN of the SNS topic that receives anomaly detection alerts."
  value       = module.detection_engine.sns_topic_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function that runs anomaly detection."
  value       = module.detection_engine.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda detector function."
  value       = module.detection_engine.lambda_function_arn
}

output "spoke_flow_log_ids" {
  description = "Map of spoke account IDs to their VPC Flow Log resource IDs."
  value       = { for k, v in module.spoke_account : k => v.flow_log_ids }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt logs and Athena results."
  value       = module.central_logging.kms_key_arn
}
