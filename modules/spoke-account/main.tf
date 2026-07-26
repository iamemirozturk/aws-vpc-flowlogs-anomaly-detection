data "aws_caller_identity" "current" {}

resource "aws_flow_log" "vpc" {
  for_each = var.vpc_ids

  vpc_id                   = each.value
  traffic_type             = var.flow_log_traffic_type
  log_destination          = var.central_log_bucket_arn
  log_destination_type     = "s3"
  log_format               = var.flow_log_format
  max_aggregation_interval = var.max_aggregation_interval

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.spoke_account_id
      error_message = "The active AWS credentials do not belong to spoke_account_id."
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.environment}-flowlog-${each.value}"
    VpcId     = each.value
    AccountId = var.spoke_account_id
  })
}
