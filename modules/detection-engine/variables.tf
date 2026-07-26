variable "central_account_id" {
  description = "Account ID that owns the detector resources."
  type        = string
}

variable "athena_workgroup_name" {
  description = "Athena workgroup used by the detector."
  type        = string
}

variable "athena_database_name" {
  description = "Glue database queried by the detector."
  type        = string
}

variable "athena_table_name" {
  description = "Glue table queried by the detector."
  type        = string
  default     = "flow_logs"
}

variable "athena_results_bucket" {
  description = "Bucket receiving Athena query results."
  type        = string
}

variable "exfil_threshold_bytes" {
  description = "Outbound bytes per source entity that triggers an alert."
  type        = number
}

variable "excluded_destination_cidrs" {
  description = "Additional destination CIDRs excluded from alerts."
  type        = list(string)
  default     = []
}

variable "detection_window_minutes" {
  description = "Length of a detector query window."
  type        = number
  default     = 60
}

variable "data_delay_minutes" {
  description = "Delay before querying a completed Flow Logs window."
  type        = number
  default     = 15
}

variable "max_alerts_per_run" {
  description = "Maximum entities included in one notification."
  type        = number
  default     = 25

  validation {
    condition     = var.max_alerts_per_run >= 1 && var.max_alerts_per_run <= 100
    error_message = "max_alerts_per_run must be between 1 and 100."
  }
}

variable "alert_email" {
  description = "Optional email endpoint for the SNS topic."
  type        = string
  default     = null
  nullable    = true
}

variable "detection_schedule" {
  description = "EventBridge schedule expression."
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "Detector Lambda execution role ARN."
  type        = string
}

variable "lambda_execution_role_name" {
  description = "Detector Lambda execution role name."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period."
  type        = number
  default     = 365
}

variable "environment" {
  description = "Environment name used in resource names."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags applied to detector resources."
  type        = map(string)
  default     = {}
}
