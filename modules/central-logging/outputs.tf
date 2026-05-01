output "log_bucket_name"            { value = aws_s3_bucket.central_logs.bucket }
output "log_bucket_arn"             { value = aws_s3_bucket.central_logs.arn }
output "kms_key_arn"                { value = aws_kms_key.flowlogs.arn }
output "glue_database_name"         { value = aws_glue_catalog_database.flowlogs.name }
output "athena_workgroup_name"      { value = aws_athena_workgroup.flowlogs.name }
output "athena_results_bucket_name" { value = aws_s3_bucket.athena_results.bucket }
output "lambda_execution_role_arn"  { value = aws_iam_role.lambda_execution.arn }
