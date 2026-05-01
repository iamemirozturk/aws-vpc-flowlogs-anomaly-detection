variable "central_account_id"        { type = string }
variable "log_bucket_name"            { type = string }
variable "athena_workgroup_name"      { type = string }
variable "athena_database_name"       { type = string }
variable "athena_results_bucket"      { type = string }
variable "exfil_threshold_bytes"      { type = number }
variable "alert_email"                { type = string }
variable "detection_schedule"         { type = string }
variable "lambda_execution_role_arn"  { type = string }
variable "environment"                { type = string; default = "prod" }
variable "tags"                       { type = map(string); default = {} }
