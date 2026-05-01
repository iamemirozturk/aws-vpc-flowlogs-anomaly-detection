variable "spoke_account_id"       { type = string }
variable "vpc_ids"                 { type = list(string) }
variable "central_account_id"     { type = string }
variable "central_log_bucket"     { type = string }
variable "central_log_bucket_arn" { type = string }
variable "flow_log_traffic_type"  { type = string; default = "ALL" }
variable "environment"            { type = string; default = "prod" }
variable "tags"                   { type = map(string); default = {} }

variable "flow_log_format" {
  description = "Custom flow log format. Leave empty for AWS default."
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
}
