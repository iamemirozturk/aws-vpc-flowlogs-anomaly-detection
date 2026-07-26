output "log_bucket_name" {
  description = "Central Flow Logs bucket name."
  value       = aws_s3_bucket.central_logs.bucket
}

output "log_bucket_arn" {
  description = "Central Flow Logs bucket ARN."
  value       = aws_s3_bucket.central_logs.arn
}

output "kms_key_arn" {
  description = "KMS key protecting logs and Athena results."
  value       = aws_kms_key.flowlogs.arn
}

output "glue_database_name" {
  description = "Glue database name."
  value       = aws_glue_catalog_database.flowlogs.name
}

output "glue_table_name" {
  description = "Partition-projected Glue table name."
  value       = aws_glue_catalog_table.flowlogs.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name."
  value       = aws_athena_workgroup.flowlogs.name
}

output "athena_results_bucket_name" {
  description = "Athena results bucket name."
  value       = aws_s3_bucket.athena_results.bucket
}

output "lambda_execution_role_arn" {
  description = "Execution role ARN used by the detector."
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Execution role name used for detector-specific policy attachment."
  value       = aws_iam_role.lambda_execution.name
}

output "lifecycle_transition_minimum_object_size" {
  description = "Effective S3 lifecycle minimum-object-size transition behavior."
  value       = aws_s3_bucket_lifecycle_configuration.central_logs.transition_default_minimum_object_size
}
