output "flow_log_ids" {
  description = "Map of VPC ID to Flow Log ID."
  value       = { for vpc_id, flow_log in aws_flow_log.vpc : vpc_id => flow_log.id }
}

output "log_destination" {
  description = "Central S3 bucket ARN configured on each Flow Log."
  value       = var.central_log_bucket_arn
}
