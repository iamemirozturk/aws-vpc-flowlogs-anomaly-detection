variable "central_account_id" {
  description = "Twelve-digit ID of the Security/Logging account where central resources are deployed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.central_account_id))
    error_message = "central_account_id must be a 12-digit AWS account ID."
  }
}

variable "central_region" {
  description = "AWS Region for the central logging and detection resources."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.central_region))
    error_message = "central_region must be a valid AWS Region identifier."
  }
}

variable "log_bucket_name" {
  description = "Globally unique name for the central VPC Flow Logs bucket. Limited to 48 characters so derived bucket names remain valid."
  type        = string

  validation {
    condition = (
      length(var.log_bucket_name) >= 3 &&
      length(var.log_bucket_name) <= 48 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.log_bucket_name)) &&
      !can(regex("\\.\\.", var.log_bucket_name)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.log_bucket_name))
    )
    error_message = "log_bucket_name must be a valid 3-48 character S3 bucket name."
  }
}

variable "log_sources" {
  description = "Spoke account and Region combinations permitted to deliver VPC Flow Logs and exposed through partition projection."
  type = list(object({
    account_id = string
    regions    = set(string)
  }))

  validation {
    condition = (
      length(var.log_sources) > 0 &&
      alltrue([
        for source in var.log_sources :
        can(regex("^[0-9]{12}$", source.account_id)) &&
        length(source.regions) > 0 &&
        alltrue([
          for region in source.regions :
          can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", region))
        ])
      ])
    )
    error_message = "log_sources must contain at least one valid account ID with at least one valid AWS Region."
  }
}

variable "exfil_threshold_bytes" {
  description = "Outbound bytes per source entity in one detection window that triggers an alert."
  type        = number
  default     = 53687091200

  validation {
    condition     = var.exfil_threshold_bytes > 0 && floor(var.exfil_threshold_bytes) == var.exfil_threshold_bytes
    error_message = "exfil_threshold_bytes must be a positive integer."
  }
}

variable "alert_email" {
  description = "Optional email endpoint for SNS alerts. The subscription remains pending until the recipient confirms it."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.alert_email == null ||
      can(regex("^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    )
    error_message = "alert_email must be null or a valid email address."
  }
}

variable "detection_window_minutes" {
  description = "Length and invocation interval of each detector window, in whole minutes."
  type        = number
  default     = 60

  validation {
    condition = (
      var.detection_window_minutes >= 5 &&
      var.detection_window_minutes <= 1440 &&
      floor(var.detection_window_minutes) == var.detection_window_minutes
    )
    error_message = "detection_window_minutes must be an integer between 5 and 1440."
  }
}

variable "data_delay_minutes" {
  description = "Delay applied to the query window to allow Flow Logs delivery to complete."
  type        = number
  default     = 15

  validation {
    condition     = var.data_delay_minutes >= 0 && var.data_delay_minutes <= 180
    error_message = "data_delay_minutes must be between 0 and 180."
  }
}

variable "excluded_destination_cidrs" {
  description = "Additional destination CIDRs excluded from exfiltration alerts."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.excluded_destination_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every excluded_destination_cidrs entry must be valid CIDR notation."
  }
}

variable "glacier_transition_days" {
  description = "Days before current Flow Log objects transition to Glacier Flexible Retrieval."
  type        = number
  default     = 90

  validation {
    condition     = var.glacier_transition_days >= 30
    error_message = "glacier_transition_days must be at least 30."
  }
}

variable "deep_archive_transition_days" {
  description = "Days before current Flow Log objects transition to Glacier Deep Archive."
  type        = number
  default     = 180

  validation {
    condition     = var.deep_archive_transition_days >= 90
    error_message = "deep_archive_transition_days must be at least 90."
  }
}

variable "log_expiration_days" {
  description = "Optional number of days before current Flow Log objects expire. Null retains them indefinitely."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.log_expiration_days == null || var.log_expiration_days >= 1
    error_message = "log_expiration_days must be null or a positive number."
  }
}

variable "athena_results_bucket_name" {
  description = "Optional globally unique Athena results bucket name. A name derived from log_bucket_name is used when null."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.athena_results_bucket_name == null ||
      (
        length(var.athena_results_bucket_name) >= 3 &&
        length(var.athena_results_bucket_name) <= 63 &&
        can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.athena_results_bucket_name))
      )
    )
    error_message = "athena_results_bucket_name must be null or a valid S3 bucket name."
  }
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock at bucket creation. This setting cannot be disabled later."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Default Object Lock retention mode when Object Lock is enabled."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Default Object Lock retention in days."
  type        = number
  default     = 365

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "object_lock_retention_days must be positive."
  }
}

variable "athena_query_scan_cutoff_bytes" {
  description = "Maximum bytes that Athena permits a single workgroup query to scan."
  type        = number
  default     = 10737418240

  validation {
    condition     = var.athena_query_scan_cutoff_bytes >= 10485760
    error_message = "athena_query_scan_cutoff_bytes must be at least 10 MiB."
  }
}

variable "environment" {
  description = "Short environment name used in resource names."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric or hyphen characters and start with a letter."
  }
}

variable "project_name" {
  description = "Project tag applied to all resources."
  type        = string
  default     = "vpc-flowlogs-anomaly-detection"
}

variable "tags" {
  description = "Additional tags applied to resources."
  type        = map(string)
  default     = {}
}
