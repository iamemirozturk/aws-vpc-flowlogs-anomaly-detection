# ---------------------------------------------------------------------------
# Root Main — VPC Flow Logs Centralized Anomaly Detection
# ---------------------------------------------------------------------------

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "security-team"
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# Module: Central Logging Account Resources
# ---------------------------------------------------------------------------
module "central_logging" {
  source = "./modules/central-logging"

  providers = {
    aws = aws.central
  }

  central_account_id         = var.central_account_id
  log_bucket_name            = var.log_bucket_name
  spoke_account_ids          = [for a in var.spoke_accounts : a.account_id]
  enable_object_lock         = var.enable_object_lock
  object_lock_retention_days = var.object_lock_retention_days
  log_retention_days         = var.log_retention_days
  athena_results_bucket      = var.athena_results_bucket
  glue_crawler_schedule      = var.glue_crawler_schedule
  environment                = var.environment
  tags                       = local.common_tags
}

# ---------------------------------------------------------------------------
# Module: Spoke Account Resources (one per spoke account)
# ---------------------------------------------------------------------------
module "spoke_account" {
  source   = "./modules/spoke-account"
  for_each = { for a in var.spoke_accounts : a.account_id => a }

  spoke_account_id      = each.value.account_id
  vpc_ids               = each.value.vpc_ids
  central_account_id    = var.central_account_id
  central_log_bucket    = module.central_logging.log_bucket_name
  central_log_bucket_arn = module.central_logging.log_bucket_arn
  flow_log_traffic_type = var.flow_log_traffic_type
  environment           = var.environment
  tags                  = local.common_tags

  # Each spoke account is accessed via assume_role from the deploying principal.
  # Set AWS_PROFILE or configure credentials per account in your CI environment.
}

# ---------------------------------------------------------------------------
# Module: Detection Engine (Lambda + EventBridge + SNS)
# ---------------------------------------------------------------------------
module "detection_engine" {
  source = "./modules/detection-engine"

  providers = {
    aws = aws.central
  }

  central_account_id          = var.central_account_id
  log_bucket_name             = module.central_logging.log_bucket_name
  athena_workgroup_name       = module.central_logging.athena_workgroup_name
  athena_database_name        = module.central_logging.glue_database_name
  athena_results_bucket       = module.central_logging.athena_results_bucket_name
  exfil_threshold_bytes       = var.exfil_threshold_bytes
  alert_email                 = var.alert_email
  detection_schedule          = var.detection_schedule
  lambda_execution_role_arn   = module.central_logging.lambda_execution_role_arn
  environment                 = var.environment
  tags                        = local.common_tags

  depends_on = [module.central_logging]
}
