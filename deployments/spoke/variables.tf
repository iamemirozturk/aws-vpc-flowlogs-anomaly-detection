variable "spoke_account_id" {
  description = "Account that owns the VPCs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.spoke_account_id))
    error_message = "spoke_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region containing the VPCs."
  type        = string
  default     = "us-east-1"
}

variable "deployment_role_arn" {
  description = "Role assumed by Terraform in the spoke account."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.deployment_role_arn))
    error_message = "deployment_role_arn must be an IAM role ARN."
  }
}

variable "vpc_ids" {
  description = "VPCs on which to enable Flow Logs."
  type        = set(string)
}

variable "central_log_bucket_arn" {
  description = "central_log_bucket_arn output from the central root deployment."
  type        = string
}

variable "flow_log_traffic_type" {
  description = "Traffic type captured by VPC Flow Logs."
  type        = string
  default     = "ALL"
}

variable "max_aggregation_interval" {
  description = "Maximum Flow Log aggregation interval in seconds."
  type        = number
  default     = 60
}

variable "environment" {
  description = "Environment name used in tags."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project tag."
  type        = string
  default     = "vpc-flowlogs-anomaly-detection"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
