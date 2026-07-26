data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  function_name    = "${var.environment}-flowlogs-detector"
  log_group_name   = "/aws/lambda/${local.function_name}"
  topic_name       = "${var.environment}-flowlogs-alerts"
  state_table_name = "${var.environment}-flowlogs-detection-state"
  schedule_expression = format(
    "rate(%d minutes)",
    var.detection_window_minutes,
  )
  log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${var.central_account_id}:log-group:${local.log_group_name}"
  topic_arn     = "arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.region}:${var.central_account_id}:${local.topic_name}"
}

data "archive_file" "detector" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/detector.py"
  output_path = "${path.module}/../../lambda/detector.zip"
}

data "aws_iam_policy_document" "alerts_kms_key" {
  #checkov:skip=CKV_AWS_109:An account-root kms:* statement is the AWS KMS key-policy mechanism that enables IAM delegation.
  #checkov:skip=CKV_AWS_111:KMS key policies require Resource "*" because the key ARN is not available while constructing its own policy.
  #checkov:skip=CKV_AWS_356:Service grants are constrained by principal, source, and encryption context; Resource "*" is required here.
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
    sid    = "AllowSNSService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.central_account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:sns:topicArn"
      values   = [local.topic_arn]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsService"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt*",
      "kms:Describe*",
      "kms:Encrypt*",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.log_group_arn]
    }
  }

  statement {
    sid    = "AllowCloudWatchAlarmEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.central_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.region}:${var.central_account_id}:alarm:${var.environment}-flowlogs-*",
      ]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "Protects Flow Logs alerts, detector state, and Lambda logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.alerts_kms_key.json

  tags = merge(var.tags, {
    Name = "${var.environment}-flowlogs-alerts"
  })
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.environment}-flowlogs-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowAccountAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.central_account_id}:root"]
    }

    actions   = ["sns:*"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowDetectorPublish"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.lambda_execution_role_arn]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAlarmPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.central_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.region}:${var.central_account_id}:alarm:${var.environment}-flowlogs-*",
      ]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_dynamodb_table" "detection_state" {
  name         = local.state_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "detection_key"

  attribute {
    name = "detection_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.alerts.arn
  }

  tags = var.tags
}

resource "aws_sqs_queue" "detector_dlq" {
  name                      = "${var.environment}-flowlogs-detector-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

data "aws_iam_policy_document" "detector_dlq" {
  statement {
    sid    = "AllowEventBridgeSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.detector_dlq.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.detector_schedule.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.central_account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "detector_dlq" {
  queue_url = aws_sqs_queue.detector_dlq.id
  policy    = data.aws_iam_policy_document.detector_dlq.json
}

resource "aws_cloudwatch_log_group" "detector" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.alerts.arn

  tags = var.tags
}

data "aws_iam_policy_document" "detector_runtime" {
  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid = "UseAlertsKMSKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.alerts.arn]
  }

  statement {
    sid = "ManageDetectionState"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
    ]
    resources = [aws_dynamodb_table.detection_state.arn]
  }

  statement {
    sid       = "SendFailedAsyncInvocation"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.detector_dlq.arn]
  }
}

resource "aws_iam_role_policy" "detector_runtime" {
  name   = "flowlogs-alerting-and-state"
  role   = var.lambda_execution_role_name
  policy = data.aws_iam_policy_document.detector_runtime.json
}

resource "aws_lambda_function" "detector" {
  #checkov:skip=CKV_AWS_117:The function calls regional AWS APIs only; VPC attachment would require NAT/endpoints and add cost/attack surface.
  #checkov:skip=CKV_AWS_272:The locally archived source is hash-pinned and CI-scanned; AWS Signer automation is outside this reference.
  function_name                  = local.function_name
  description                    = "Queries Athena for high-volume external egress and publishes aggregated alerts"
  role                           = var.lambda_execution_role_arn
  filename                       = data.archive_file.detector.output_path
  source_code_hash               = data.archive_file.detector.output_base64sha256
  handler                        = "detector.lambda_handler"
  runtime                        = "python3.12"
  architectures                  = ["arm64"]
  timeout                        = 360
  memory_size                    = 256
  reserved_concurrent_executions = 1
  kms_key_arn                    = aws_kms_key.alerts.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.detector_dlq.arn
  }

  environment {
    variables = {
      ATHENA_DATABASE            = var.athena_database_name
      ATHENA_TABLE               = var.athena_table_name
      ATHENA_WORKGROUP           = var.athena_workgroup_name
      ATHENA_RESULTS_BUCKET      = "s3://${var.athena_results_bucket}/results/"
      SNS_TOPIC_ARN              = aws_sns_topic.alerts.arn
      DETECTION_STATE_TABLE      = aws_dynamodb_table.detection_state.name
      EXFIL_THRESHOLD_BYTES      = tostring(var.exfil_threshold_bytes)
      DETECTION_WINDOW_MINUTES   = tostring(var.detection_window_minutes)
      DATA_DELAY_MINUTES         = tostring(var.data_delay_minutes)
      EXCLUDED_DESTINATION_CIDRS = jsonencode(var.excluded_destination_cidrs)
      MAX_ALERTS_PER_RUN         = tostring(var.max_alerts_per_run)
      ENVIRONMENT                = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.detector,
    aws_iam_role_policy.detector_runtime,
  ]

  tags = var.tags
}

resource "aws_lambda_function_event_invoke_config" "detector" {
  function_name                = aws_lambda_function.detector.function_name
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 2
}

resource "aws_cloudwatch_event_rule" "detector_schedule" {
  name                = "${var.environment}-flowlogs-detector-schedule"
  description         = "Runs the VPC Flow Logs anomaly detector"
  schedule_expression = local.schedule_expression
  state               = "ENABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "detector" {
  rule      = aws_cloudwatch_event_rule.detector_schedule.name
  target_id = "FlowLogsDetectorLambda"
  arn       = aws_lambda_function.detector.arn

  dead_letter_config {
    arn = aws_sqs_queue.detector_dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 2
  }

  depends_on = [aws_sqs_queue_policy.detector_dlq]
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id   = "AllowEventBridgeInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.detector.function_name
  principal      = "events.amazonaws.com"
  source_arn     = aws_cloudwatch_event_rule.detector_schedule.arn
  source_account = var.central_account_id
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.environment}-flowlogs-lambda-errors"
  alarm_description   = "Detector Lambda returned one or more errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.detector.function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.environment}-flowlogs-lambda-throttles"
  alarm_description   = "Detector Lambda was throttled"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.detector.function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.environment}-flowlogs-dlq-messages"
  alarm_description   = "A detector invocation or EventBridge delivery exhausted retries"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.detector_dlq.name
  }

  tags = var.tags
}
