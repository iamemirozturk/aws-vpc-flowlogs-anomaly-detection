output "flow_log_ids" {
  description = "Map of VPC IDs to Flow Log IDs."
  value       = module.vpc_flow_logs.flow_log_ids
}
