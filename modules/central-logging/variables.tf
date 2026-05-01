variable "central_account_id" { type = string }
variable "log_bucket_name" { type = string }
variable "spoke_account_ids" { type = list(string) }
variable "enable_object_lock" { type = bool; default = true }
variable "object_lock_retention_days" { type = number; default = 365 }
variable "log_retention_days" { type = number; default = 90 }
variable "athena_results_bucket" { type = string; default = "" }
variable "glue_crawler_schedule" { type = string; default = "cron(0 2 * * ? *)" }
variable "environment" { type = string; default = "prod" }
variable "tags" { type = map(string); default = {} }
