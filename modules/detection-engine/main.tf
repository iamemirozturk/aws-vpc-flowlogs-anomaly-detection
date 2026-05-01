# ---------------------------------------------------------------------------
# Module: detection-engine
# Lambda function + EventBridge schedule + SNS alerts
# ---------------------------------------------------------------------------

data "aws_region" "current" {}

data "archive_file" "detector" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/detector.py"
  output_path = "${path.module}/../../lambda/detector.zip"
}

# ---------------------------------------------------------------------------
# SNS Topic for Alerts
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-flowlogs-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

data "aws_iam_policy_document" "sns_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = [var.lambda_execution_role_arn]
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group for Lambda
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "detector" {
  name              = "/aws/lambda/${var.environment}-flowlogs-detector"
  retention_in_days = 30

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "detector" {
  function_name    = "${var.environment}-flowlogs-detector"
  description      = "Queries Athena for anomalous VPC Flow Log traffic and publishes SNS alerts"
  role             = var.lambda_execution_role_arn
  filename         = data.archive_file.detector.output_path
  source_code_hash = data.archive_file.detector.output_base64sha256
  handler          = "detector.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      ATHENA_DATABASE        = var.athena_database_name
      ATHENA_WORKGROUP       = var.athena_workgroup_name
      ATHENA_RESULTS_BUCKET  = "s3://${var.athena_results_bucket}/results/"
      SNS_TOPIC_ARN          = aws_sns_topic.alerts.arn
      EXFIL_THRESHOLD_BYTES  = tostring(var.exfil_threshold_bytes)
      LOG_BUCKET             = var.log_bucket_name
      ENVIRONMENT            = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.detector]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge Rule — Schedule
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "detector_schedule" {
  name                = "${var.environment}-flowlogs-detector-schedule"
  description         = "Triggers Lambda anomaly detector on schedule"
  schedule_expression = var.detection_schedule
  state               = "ENABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "detector" {
  rule      = aws_cloudwatch_event_rule.detector_schedule.name
  target_id = "FlowLogsDetectorLambda"
  arn       = aws_lambda_function.detector.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.detector_schedule.arn
}
