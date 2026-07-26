variable "central_account_id" {
  description = "Account ID that owns the central resources."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.central_account_id))
    error_message = "central_account_id must be a 12-digit AWS account ID."
  }
}

variable "log_bucket_name" {
  description = "Name of the central Flow Logs bucket."
  type        = string

  validation {
    condition     = length(var.log_bucket_name) >= 3 && length(var.log_bucket_name) <= 48
    error_message = "log_bucket_name must be 3-48 characters."
  }
}

variable "log_sources" {
  description = "Allowed source accounts and Regions for VPC Flow Log delivery and partition projection."
  type = list(object({
    account_id = string
    regions    = set(string)
  }))

  validation {
    condition = (
      length(var.log_sources) > 0 &&
      alltrue([
        for source in var.log_sources :
        can(regex("^[0-9]{12}$", source.account_id)) && length(source.regions) > 0
      ])
    )
    error_message = "log_sources must contain at least one account with at least one Region."
  }
}

variable "enable_object_lock" {
  description = "Enable Object Lock when the central bucket is created."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object Lock default retention mode."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Object Lock default retention in days."
  type        = number
  default     = 365
}

variable "glacier_transition_days" {
  description = "Days before current objects transition to Glacier Flexible Retrieval."
  type        = number
  default     = 90
}

variable "deep_archive_transition_days" {
  description = "Days before current objects transition to Glacier Deep Archive."
  type        = number
  default     = 180
}

variable "log_expiration_days" {
  description = "Optional expiration for current Flow Log objects."
  type        = number
  default     = null
  nullable    = true
}

variable "athena_results_bucket_name" {
  description = "Optional Athena results bucket name."
  type        = string
  default     = null
  nullable    = true
}

variable "athena_query_scan_cutoff_bytes" {
  description = "Per-query bytes-scanned cutoff enforced by the Athena workgroup."
  type        = number
  default     = 10737418240
}

variable "environment" {
  description = "Environment name used in resource names."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags applied to module resources."
  type        = map(string)
  default     = {}
}
