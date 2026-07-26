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

module "central_logging" {
  source = "./modules/central-logging"

  central_account_id             = var.central_account_id
  log_bucket_name                = var.log_bucket_name
  log_sources                    = var.log_sources
  enable_object_lock             = var.enable_object_lock
  object_lock_mode               = var.object_lock_mode
  object_lock_retention_days     = var.object_lock_retention_days
  glacier_transition_days        = var.glacier_transition_days
  deep_archive_transition_days   = var.deep_archive_transition_days
  log_expiration_days            = var.log_expiration_days
  athena_results_bucket_name     = var.athena_results_bucket_name
  athena_query_scan_cutoff_bytes = var.athena_query_scan_cutoff_bytes
  environment                    = var.environment
  tags                           = local.common_tags
}

module "detection_engine" {
  source = "./modules/detection-engine"

  central_account_id         = var.central_account_id
  athena_workgroup_name      = module.central_logging.athena_workgroup_name
  athena_database_name       = module.central_logging.glue_database_name
  athena_table_name          = module.central_logging.glue_table_name
  athena_results_bucket      = module.central_logging.athena_results_bucket_name
  exfil_threshold_bytes      = var.exfil_threshold_bytes
  excluded_destination_cidrs = var.excluded_destination_cidrs
  detection_window_minutes   = var.detection_window_minutes
  data_delay_minutes         = var.data_delay_minutes
  alert_email                = var.alert_email
  detection_schedule         = var.detection_schedule
  lambda_execution_role_arn  = module.central_logging.lambda_execution_role_arn
  lambda_execution_role_name = module.central_logging.lambda_execution_role_name
  environment                = var.environment
  tags                       = local.common_tags

  depends_on = [module.central_logging]
}
