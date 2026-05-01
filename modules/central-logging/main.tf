# ---------------------------------------------------------------------------
# Module: central-logging
# Creates all resources in the Security/Logging account:
#   - KMS CMK
#   - Central S3 log bucket (with Object Lock, lifecycle, access logging)
#   - S3 Athena results bucket
#   - Glue Database + Crawler
#   - Athena Workgroup
#   - IAM role for Lambda
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# KMS Customer Managed Key
# ---------------------------------------------------------------------------
resource "aws_kms_key" "flowlogs" {
  description             = "CMK for VPC Flow Logs central bucket and Athena results"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_key_policy.json

  tags = merge(var.tags, {
    Name = "${var.environment}-flowlogs-cmk"
  })
}

resource "aws_kms_alias" "flowlogs" {
  name          = "alias/${var.environment}-vpc-flowlogs"
  target_key_id = aws_kms_key.flowlogs.key_id
}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.central_account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow VPC Flow Logs Service"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Allow Athena and Glue"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["athena.amazonaws.com", "glue.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:Encrypt",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Access Logging Bucket (for central log bucket's server access logs)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "access_logs" {
  bucket        = "${var.log_bucket_name}-access-logs"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.log_bucket_name}-access-logs"
    Purpose = "s3-server-access-logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Central VPC Flow Logs S3 Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "central_logs" {
  bucket        = var.log_bucket_name
  force_destroy = false

  # Object Lock must be enabled at bucket creation time
  object_lock_enabled = var.enable_object_lock

  tags = merge(var.tags, {
    Name    = var.log_bucket_name
    Purpose = "vpc-flow-logs-central"
  })
}

resource "aws_s3_bucket_public_access_block" "central_logs" {
  bucket                  = aws_s3_bucket.central_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flowlogs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "central_logs" {
  bucket        = aws_s3_bucket.central_logs.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = var.log_retention_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.log_retention_days * 3
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "central_logs" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.central_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id
  policy = data.aws_iam_policy_document.central_logs_bucket_policy.json
}

data "aws_iam_policy_document" "central_logs_bucket_policy" {
  # Deny all non-HTTPS access
  statement {
    sid    = "DenyNonSecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.central_logs.arn,
      "${aws_s3_bucket.central_logs.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow VPC Flow Logs service to deliver logs
  statement {
    sid    = "AllowFlowLogsDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions = [
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.central_logs.arn}/AWSLogs/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = var.spoke_account_ids
    }
  }

  # Allow spoke accounts to check bucket ACL (required by flow logs service)
  statement {
    sid    = "AllowFlowLogsAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.central_logs.arn]
  }

  # Allow Glue and Athena to read logs
  statement {
    sid    = "AllowGlueAthenaRead"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.glue_crawler.arn,
        aws_iam_role.lambda_execution.arn,
      ]
    }
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.central_logs.arn,
      "${aws_s3_bucket.central_logs.arn}/*",
    ]
  }
}

# ---------------------------------------------------------------------------
# Athena Results Bucket
# ---------------------------------------------------------------------------
locals {
  athena_results_bucket_name = var.athena_results_bucket != "" ? var.athena_results_bucket : "${var.log_bucket_name}-athena-results"
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = local.athena_results_bucket_name
  force_destroy = true

  tags = merge(var.tags, {
    Name    = local.athena_results_bucket_name
    Purpose = "athena-query-results"
  })
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flowlogs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id     = "expire-query-results"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

# ---------------------------------------------------------------------------
# Glue Database
# ---------------------------------------------------------------------------
resource "aws_glue_catalog_database" "flowlogs" {
  name        = "${replace(var.environment, "-", "_")}_vpc_flow_logs"
  description = "Glue database for VPC Flow Logs from all spoke accounts"
}

# ---------------------------------------------------------------------------
# Glue IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "glue_crawler" {
  name = "${var.environment}-flowlogs-glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_kms" {
  name = "glue-s3-kms-access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.central_logs.arn,
          "${aws_s3_bucket.central_logs.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = [aws_kms_key.flowlogs.arn]
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Glue Crawler
# ---------------------------------------------------------------------------
resource "aws_glue_crawler" "flowlogs" {
  name          = "${var.environment}-vpc-flowlogs-crawler"
  database_name = aws_glue_catalog_database.flowlogs.name
  role          = aws_iam_role.glue_crawler.arn
  schedule      = var.glue_crawler_schedule
  description   = "Crawls the central VPC Flow Logs bucket and updates Glue catalog partitions"

  s3_target {
    path = "s3://${aws_s3_bucket.central_logs.bucket}/AWSLogs/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Athena Workgroup
# ---------------------------------------------------------------------------
resource "aws_athena_workgroup" "flowlogs" {
  name        = "${var.environment}-vpc-flowlogs"
  description = "Athena workgroup for VPC Flow Log analysis"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10737418240 # 10 GB — cost guard

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.flowlogs.arn
      }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lambda Execution IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_execution" {
  name = "${var.environment}-flowlogs-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "flowlogs-lambda-permissions"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
        ]
        Resource = [
          "arn:aws:athena:${data.aws_region.current.name}:${var.central_account_id}:workgroup/${var.environment}-vpc-flowlogs",
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.central_logs.arn,
          "${aws_s3_bucket.central_logs.arn}/*",
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*",
        ]
      },
      {
        Sid    = "GlueReadAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:Encrypt",
        ]
        Resource = [aws_kms_key.flowlogs.arn]
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          "arn:aws:sns:${data.aws_region.current.name}:${var.central_account_id}:${var.environment}-flowlogs-alerts",
        ]
      },
    ]
  })
}
