# ---------------------------------------------------------------------------
# Root Variables
# ---------------------------------------------------------------------------

variable "central_account_id" {
  description = "AWS Account ID of the central Security/Logging account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.central_account_id))
    error_message = "central_account_id must be a 12-digit AWS account ID."
  }
}

variable "central_region" {
  description = "AWS region for the central logging account resources."
  type        = string
  default     = "us-east-1"
}

variable "log_bucket_name" {
  description = "Name of the central S3 bucket that receives VPC Flow Logs from all spoke accounts."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{2,61}[a-z0-9]$", var.log_bucket_name))
    error_message = "log_bucket_name must be a valid S3 bucket name (lowercase, 3-63 chars)."
  }
}

variable "spoke_accounts" {
  description = <<-EOT
    List of spoke accounts to onboard.
    Each entry specifies the account ID and the list of VPC IDs to enable Flow Logs on.
    The module will assume the deployment role in each account.
  EOT
  type = list(object({
    account_id = string
    vpc_ids    = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.spoke_accounts : can(regex("^[0-9]{12}$", a.account_id))
    ])
    error_message = "Each spoke account_id must be a 12-digit AWS account ID."
  }
}

variable "exfil_threshold_bytes" {
  description = "Bytes transferred in a detection window above which an alert is triggered. Default: 50 GB."
  type        = number
  default     = 53687091200 # 50 * 1024^3

  validation {
    condition     = var.exfil_threshold_bytes > 0
    error_message = "exfil_threshold_bytes must be a positive integer."
  }
}

variable "alert_email" {
  description = "Email address to receive SNS anomaly detection alerts."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "detection_schedule" {
  description = "EventBridge schedule expression for the Lambda detector. Default: every hour."
  type        = string
  default     = "rate(1 hour)"
}

variable "log_retention_days" {
  description = "S3 lifecycle rule: move logs to Glacier after this many days."
  type        = number
  default     = 90
}

variable "athena_results_bucket" {
  description = "S3 bucket for Athena query results. If empty, a bucket is created automatically."
  type        = string
  default     = ""
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock (COMPLIANCE mode) for log immutability. Cannot be disabled after creation."
  type        = bool
  default     = true
}

variable "object_lock_retention_days" {
  description = "Number of days for S3 Object Lock COMPLIANCE retention."
  type        = number
  default     = 365
}

variable "glue_crawler_schedule" {
  description = "Cron schedule for the Glue Crawler. Default: daily at 02:00 UTC."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "flow_log_traffic_type" {
  description = "Type of traffic to capture in VPC Flow Logs. Options: ACCEPT, REJECT, ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be one of: ACCEPT, REJECT, ALL."
  }
}

variable "environment" {
  description = "Deployment environment (e.g., prod, staging)."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Name tag applied to all resources."
  type        = string
  default     = "vpc-flowlogs-anomaly-detection"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
