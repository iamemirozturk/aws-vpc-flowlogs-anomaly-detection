locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      DataClass   = "SecurityTelemetry"
    },
    var.tags
  )
}

module "vpc_flow_logs" {
  source = "../../modules/spoke-account"

  spoke_account_id         = var.spoke_account_id
  vpc_ids                  = var.vpc_ids
  central_log_bucket_arn   = var.central_log_bucket_arn
  flow_log_traffic_type    = var.flow_log_traffic_type
  max_aggregation_interval = var.max_aggregation_interval
  environment              = var.environment
  tags                     = local.common_tags
}
