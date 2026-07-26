"""Static contracts for the Terraform policy boundaries.

Terraform mock providers replace aws_iam_policy_document outputs, so these tests
inspect the reviewed HCL blocks directly. Sandbox integration tests should still
validate the rendered JSON before a release.
"""

from __future__ import annotations

from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[1]


def _block(source: str, header: str) -> str:
    """Return one balanced HCL block, including interpolated braces."""
    start = source.index(header)
    opening_brace = source.index("{", start)
    depth = 0

    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start: index + 1]

    raise AssertionError(f"Unterminated HCL block: {header}")


def test_flow_log_delivery_policy_pairs_source_and_destination() -> None:
    source = (REPOSITORY_ROOT / "modules/central-logging/main.tf").read_text()
    policy = _block(
        source,
        'data "aws_iam_policy_document" "central_logs_bucket"',
    )

    assert 'identifiers = ["delivery.logs.amazonaws.com"]' in policy
    assert 'variable = "s3:x-amz-acl"' in policy
    assert 'values   = ["bucket-owner-full-control"]' in policy
    assert 'variable = "aws:SourceAccount"' in policy
    assert 'variable = "aws:SourceArn"' in policy
    assert "/AWSLogs/aws-account-id=${statement.value.account_id}/*" in policy


def test_flow_log_kms_policy_is_bound_to_the_bucket_context() -> None:
    source = (REPOSITORY_ROOT / "modules/central-logging/main.tf").read_text()
    policy = _block(
        source,
        'data "aws_iam_policy_document" "flowlogs_kms_key"',
    )

    assert 'identifiers = ["delivery.logs.amazonaws.com"]' in policy
    assert 'variable = "kms:EncryptionContext:aws:s3:arn"' in policy
    assert "local.central_bucket_arn" in policy


def test_failure_destinations_restrict_eventbridge_and_lambda() -> None:
    source = (REPOSITORY_ROOT / "modules/detection-engine/main.tf").read_text()
    queue_policy = _block(
        source,
        'data "aws_iam_policy_document" "detector_dlq"',
    )
    runtime_policy = _block(
        source,
        'data "aws_iam_policy_document" "detector_runtime"',
    )
    lambda_function = _block(
        source,
        'resource "aws_lambda_function" "detector"',
    )
    event_target = _block(
        source,
        'resource "aws_cloudwatch_event_target" "detector"',
    )

    assert 'identifiers = ["events.amazonaws.com"]' in queue_policy
    assert 'variable = "aws:SourceArn"' in queue_policy
    assert "aws_cloudwatch_event_rule.detector_schedule.arn" in queue_policy
    assert 'actions   = ["sqs:SendMessage"]' in runtime_policy
    assert "aws_sqs_queue.detector_dlq.arn" in runtime_policy
    assert "target_arn = aws_sqs_queue.detector_dlq.arn" in lambda_function
    assert "arn = aws_sqs_queue.detector_dlq.arn" in event_target
