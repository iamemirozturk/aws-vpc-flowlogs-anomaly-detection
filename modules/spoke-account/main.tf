# ---------------------------------------------------------------------------
# Module: spoke-account
# Enables VPC Flow Logs on specified VPCs and creates cross-account
# IAM delivery role that allows the flow logs service to write to the
# central S3 bucket.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "spoke" {}

# ---------------------------------------------------------------------------
# IAM Role — VPC Flow Logs Delivery Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "flowlogs_delivery" {
  name = "${var.environment}-vpc-flowlogs-delivery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.spoke_account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ec2:*:${var.spoke_account_id}:vpc-flow-log/*"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flowlogs_delivery_s3" {
  name = "flowlogs-cross-account-s3-delivery"
  role = aws_iam_role.flowlogs_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
        ]
        Resource = "${var.central_log_bucket_arn}/AWSLogs/${var.spoke_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl"]
        Resource = var.central_log_bucket_arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# VPC Flow Logs — one per VPC ID
# ---------------------------------------------------------------------------
resource "aws_flow_log" "vpc" {
  for_each = toset(var.vpc_ids)

  vpc_id          = each.value
  traffic_type    = var.flow_log_traffic_type
  iam_role_arn    = aws_iam_role.flowlogs_delivery.arn
  log_destination = "s3://${var.central_log_bucket}/AWSLogs/${var.spoke_account_id}/"

  log_destination_type = "s3"
  log_format           = var.flow_log_format

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tags = merge(var.tags, {
    Name      = "${var.environment}-flowlog-${each.value}"
    VpcId     = each.value
    AccountId = var.spoke_account_id
  })
}
