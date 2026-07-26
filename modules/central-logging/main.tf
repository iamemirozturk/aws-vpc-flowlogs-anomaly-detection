data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  source_pairs = flatten([
    for source in var.log_sources : [
      for region in source.regions : {
        account_id = source.account_id
        region     = region
      }
    ]
  ])
  source_pair_map = {
    for source in local.source_pairs :
    "${source.account_id}-${source.region}" => source
  }
  source_account_ids = distinct([for source in var.log_sources : source.account_id])
  source_regions     = distinct(flatten([for source in var.log_sources : tolist(source.regions)]))
  source_arns = [
    for source in local.source_pairs :
    "arn:${data.aws_partition.current.partition}:logs:${source.region}:${source.account_id}:*"
  ]
  central_bucket_arn         = "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket_name}"
  athena_results_bucket_name = coalesce(var.athena_results_bucket_name, "${var.log_bucket_name}-athena-results")
  athena_results_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.athena_results_bucket_name}"
  flowlogs_database_name     = "${replace(var.environment, "-", "_")}_vpc_flow_logs"
  flowlogs_table_name        = "flow_logs"
  lambda_execution_role_name = "${var.environment}-flowlogs-detector-role"
}

data "aws_iam_policy_document" "flowlogs_kms_key" {
  #checkov:skip=CKV_AWS_109:An account-root kms:* statement is the AWS KMS key-policy mechanism that enables IAM delegation.
  #checkov:skip=CKV_AWS_111:KMS key policies require Resource "*" because the key ARN is not available while constructing its own policy.
  #checkov:skip=CKV_AWS_356:Service grants are constrained by principal and encryption context; KMS key policies require Resource "*".
  statement {
    sid    = "EnableAccountIAMPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.central_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowVPCFlowLogsDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values = [
        local.central_bucket_arn,
        "${local.central_bucket_arn}/*",
      ]
    }
  }

}

resource "aws_kms_key" "flowlogs" {
  description             = "Protects centralized VPC Flow Logs and Athena query results"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.flowlogs_kms_key.json

  tags = merge(var.tags, {
    Name = "${var.environment}-vpc-flowlogs"
  })
}

resource "aws_kms_alias" "flowlogs" {
  name          = "alias/${var.environment}-vpc-flowlogs"
  target_key_id = aws_kms_key.flowlogs.key_id
}

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV_AWS_144:This regional reference has no cross-Region recovery target; the limitation is documented.
  #checkov:skip=CKV2_AWS_62:No event-driven consumer exists for access-log objects; access is monitored through S3/CloudTrail controls.
  #checkov:skip=CKV_AWS_145:AWS requires S3 server-access-log destinations to use SSE-S3 rather than SSE-KMS.
  bucket        = "${var.log_bucket_name}-access-logs"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${var.log_bucket_name}-access-logs"
    Purpose = "S3ServerAccessLogs"
  })
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Amazon S3 requires an access-logging destination to use SSE-S3; SSE-KMS can
# produce log objects encrypted under a key that the bucket owner cannot access.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.access_logs]
}

data "aws_iam_policy_document" "access_logs_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowS3ServerAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/logs/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.central_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        local.athena_results_bucket_arn,
        local.central_bucket_arn,
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs_bucket.json
}

resource "aws_s3_bucket" "central_logs" {
  #checkov:skip=CKV_AWS_144:This regional reference has no cross-Region recovery target; the limitation is documented.
  #checkov:skip=CKV2_AWS_62:Flow Log delivery is polled by a scheduled detector; no S3 event consumer is part of this architecture.
  bucket              = var.log_bucket_name
  force_destroy       = false
  object_lock_enabled = var.enable_object_lock

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.central_account_id
      error_message = "The active AWS credentials do not belong to central_account_id."
    }

    precondition {
      condition = (
        var.deep_archive_transition_days >= var.glacier_transition_days + 90 &&
        (
          var.log_expiration_days == null ||
          var.deep_archive_transition_days < var.log_expiration_days
        ) &&
        (
          !var.enable_object_lock ||
          var.log_expiration_days == null ||
          var.object_lock_retention_days <= var.log_expiration_days
        )
      )
      error_message = "Deep Archive must be at least 90 days after Glacier Flexible Retrieval; expiration must follow Deep Archive and Object Lock retention."
    }
  }

  tags = merge(var.tags, {
    Name    = var.log_bucket_name
    Purpose = "CentralVPCFlowLogs"
  })
}

resource "aws_s3_bucket_ownership_controls" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
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

  depends_on = [
    aws_s3_bucket_ownership_controls.access_logs,
    aws_s3_bucket_policy.access_logs,
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "central_logs" {
  bucket                                 = aws_s3_bucket.central_logs.id
  transition_default_minimum_object_size = "varies_by_storage_class"

  rule {
    id     = "flow-log-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.deep_archive_transition_days
      storage_class = "DEEP_ARCHIVE"
    }

    dynamic "expiration" {
      for_each = var.log_expiration_days == null ? [] : [var.log_expiration_days]

      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.central_logs]
}

resource "aws_s3_bucket_object_lock_configuration" "central_logs" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.central_logs.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.central_logs]
}

data "aws_iam_policy_document" "central_logs_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
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

  dynamic "statement" {
    for_each = local.source_pair_map

    content {
      sid    = "AllowDelivery${replace(statement.key, "-", "")}"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      actions = ["s3:PutObject"]
      resources = [
        "${aws_s3_bucket.central_logs.arn}/AWSLogs/aws-account-id=${statement.value.account_id}/*",
      ]

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [statement.value.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values = [
          "arn:${data.aws_partition.current.partition}:logs:${statement.value.region}:${statement.value.account_id}:*",
        ]
      }
    }
  }

  statement {
    sid    = "AllowDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.central_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.source_account_ids
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = local.source_arns
    }
  }
}

resource "aws_s3_bucket_policy" "central_logs" {
  bucket = aws_s3_bucket.central_logs.id
  policy = data.aws_iam_policy_document.central_logs_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.central_logs]
}

resource "aws_s3_bucket" "athena_results" {
  #checkov:skip=CKV_AWS_144:Query results are reproducible and intentionally regional; cross-Region replication is outside scope.
  #checkov:skip=CKV2_AWS_62:No event-driven consumer exists for query-result objects.
  bucket        = local.athena_results_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name    = local.athena_results_bucket_name
    Purpose = "AthenaQueryResults"
  })
}

resource "aws_s3_bucket_ownership_controls" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  versioning_configuration {
    status = "Enabled"
  }
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

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.athena_results]
}

data "aws_iam_policy_document" "athena_results_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  policy = data.aws_iam_policy_document.athena_results_bucket.json
}

resource "aws_s3_bucket_logging" "athena_results" {
  bucket        = aws_s3_bucket.athena_results.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "athena-results/"

  depends_on = [
    aws_s3_bucket_ownership_controls.access_logs,
    aws_s3_bucket_policy.access_logs,
  ]
}

resource "aws_glue_catalog_database" "flowlogs" {
  name        = local.flowlogs_database_name
  description = "VPC Flow Logs stored in the central security account"
}

resource "aws_glue_catalog_table" "flowlogs" {
  name          = local.flowlogs_table_name
  database_name = aws_glue_catalog_database.flowlogs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                           = "TRUE"
    classification                     = "parquet"
    "projection.enabled"               = "true"
    "projection.aws-account-id.type"   = "enum"
    "projection.aws-account-id.values" = join(",", local.source_account_ids)
    "projection.aws-service.type"      = "enum"
    "projection.aws-service.values"    = "vpcflowlogs"
    "projection.aws-region.type"       = "enum"
    "projection.aws-region.values"     = join(",", local.source_regions)
    "projection.year.type"             = "integer"
    "projection.year.range"            = "2020,2100"
    "projection.year.digits"           = "4"
    "projection.month.type"            = "integer"
    "projection.month.range"           = "1,12"
    "projection.month.digits"          = "2"
    "projection.day.type"              = "integer"
    "projection.day.range"             = "1,31"
    "projection.day.digits"            = "2"
    "projection.hour.type"             = "integer"
    "projection.hour.range"            = "0,23"
    "projection.hour.digits"           = "2"
    "storage.location.template"        = "s3://${aws_s3_bucket.central_logs.bucket}/AWSLogs/aws-account-id=$${aws-account-id}/aws-service=$${aws-service}/aws-region=$${aws-region}/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  partition_keys {
    name = "aws-account-id"
    type = "string"
  }

  partition_keys {
    name = "aws-service"
    type = "string"
  }

  partition_keys {
    name = "aws-region"
    type = "string"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.central_logs.bucket}/AWSLogs/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "version"
      type = "int"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "interface_id"
      type = "string"
    }
    columns {
      name = "srcaddr"
      type = "string"
    }
    columns {
      name = "dstaddr"
      type = "string"
    }
    columns {
      name = "srcport"
      type = "int"
    }
    columns {
      name = "dstport"
      type = "int"
    }
    columns {
      name = "protocol"
      type = "bigint"
    }
    columns {
      name = "packets"
      type = "bigint"
    }
    columns {
      name = "bytes"
      type = "bigint"
    }
    columns {
      name = "start"
      type = "bigint"
    }
    columns {
      name = "end"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "log_status"
      type = "string"
    }
    columns {
      name = "vpc_id"
      type = "string"
    }
    columns {
      name = "subnet_id"
      type = "string"
    }
    columns {
      name = "instance_id"
      type = "string"
    }
    columns {
      name = "tcp_flags"
      type = "int"
    }
    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "pkt_srcaddr"
      type = "string"
    }
    columns {
      name = "pkt_dstaddr"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "az_id"
      type = "string"
    }
    columns {
      name = "sublocation_type"
      type = "string"
    }
    columns {
      name = "sublocation_id"
      type = "string"
    }
    columns {
      name = "pkt_src_aws_service"
      type = "string"
    }
    columns {
      name = "pkt_dst_aws_service"
      type = "string"
    }
    columns {
      name = "flow_direction"
      type = "string"
    }
    columns {
      name = "traffic_path"
      type = "int"
    }
  }
}

resource "aws_athena_workgroup" "flowlogs" {
  name        = "${var.environment}-vpc-flowlogs"
  description = "Cost-controlled workgroup for VPC Flow Log detection and investigation"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_query_scan_cutoff_bytes

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

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

resource "aws_iam_role" "lambda_execution" {
  name = local.lambda_execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "lambda_data_access" {
  statement {
    sid = "AthenaQueryExecution"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
    ]
    resources = [aws_athena_workgroup.flowlogs.arn]
  }

  statement {
    sid       = "ListFlowLogObjects"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.central_logs.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["AWSLogs/*"]
    }
  }

  statement {
    sid     = "ReadFlowLogObjects"
    actions = ["s3:GetObject"]
    # Object-level S3 access requires a trailing wildcard. Scope it to the exact
    # enrolled account/Region Hive prefixes instead of the full bucket.
    # tfsec:ignore:aws-iam-no-policy-wildcards
    resources = flatten([
      for source in var.log_sources : [
        for region in source.regions :
        "${aws_s3_bucket.central_logs.arn}/AWSLogs/aws-account-id=${source.account_id}/aws-service=vpcflowlogs/aws-region=${region}/*"
      ]
    ])
  }

  statement {
    sid       = "ListAthenaResults"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.athena_results.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["results/*"]
    }
  }

  statement {
    sid = "ManageAthenaResultObjects"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/results/*",
    ]
  }

  statement {
    sid = "ReadGlueCatalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${var.central_account_id}:catalog",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${var.central_account_id}:database/${aws_glue_catalog_database.flowlogs.name}",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${var.central_account_id}:table/${aws_glue_catalog_database.flowlogs.name}/${aws_glue_catalog_table.flowlogs.name}",
    ]
  }

  statement {
    sid = "UseFlowLogsKMSKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.flowlogs.arn]
  }
}

resource "aws_iam_role_policy" "lambda_data_access" {
  name   = "flowlogs-data-access"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_data_access.json
}
