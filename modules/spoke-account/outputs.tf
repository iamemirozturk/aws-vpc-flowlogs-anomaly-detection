output "flow_log_ids" {
  description = "Map of VPC ID to Flow Log resource ID."
  value       = { for k, v in aws_flow_log.vpc : k => v.id }
}

output "delivery_role_arn" {
  description = "ARN of the cross-account delivery IAM role."
  value       = aws_iam_role.flowlogs_delivery.arn
}
