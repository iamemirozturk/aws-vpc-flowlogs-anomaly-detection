variable "spoke_account_id" {
  description = "Account that owns the VPCs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.spoke_account_id))
    error_message = "spoke_account_id must be a 12-digit AWS account ID."
  }
}

variable "vpc_ids" {
  description = "VPC IDs on which to create Flow Logs."
  type        = set(string)

  validation {
    condition     = length(var.vpc_ids) > 0 && alltrue([for id in var.vpc_ids : can(regex("^vpc-[0-9a-f]{8,17}$", id))])
    error_message = "vpc_ids must contain at least one valid VPC ID."
  }
}

variable "central_log_bucket_arn" {
  description = "ARN of the central S3 bucket. The central bucket policy, not a spoke IAM delivery role, authorizes delivery.logs.amazonaws.com."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.central_log_bucket_arn))
    error_message = "central_log_bucket_arn must be an S3 bucket ARN without a trailing slash."
  }
}

variable "flow_log_traffic_type" {
  description = "Traffic type captured by VPC Flow Logs."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT, or ALL."
  }
}

variable "max_aggregation_interval" {
  description = "Maximum Flow Log aggregation interval in seconds."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.max_aggregation_interval)
    error_message = "max_aggregation_interval must be 60 or 600 seconds."
  }
}

variable "environment" {
  description = "Environment name used in resource tags."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Additional tags applied to Flow Log resources."
  type        = map(string)
  default     = {}
}

variable "flow_log_format" {
  description = "Enriched VPC Flow Log record format used by the Glue table schema."
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
}
