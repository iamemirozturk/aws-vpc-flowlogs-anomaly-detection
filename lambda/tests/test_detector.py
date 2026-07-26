"""Unit tests for the detector's time, query, and idempotency logic."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

DETECTOR_PATH = Path(__file__).parents[1] / "detector.py"


@pytest.fixture
def detector(monkeypatch: pytest.MonkeyPatch) -> Any:
    environment = {
        "ATHENA_DATABASE": "prod_vpc_flow_logs",
        "ATHENA_TABLE": "flow_logs",
        "ATHENA_WORKGROUP": "prod-vpc-flowlogs",
        "ATHENA_RESULTS_BUCKET": "s3://results/results/",
        "SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:111122223333:alerts",
        "DETECTION_STATE_TABLE": "detection-state",
        "EXFIL_THRESHOLD_BYTES": "1000",
        "DETECTION_WINDOW_MINUTES": "60",
        "DATA_DELAY_MINUTES": "15",
        "EXCLUDED_DESTINATION_CIDRS": '["203.0.113.0/24"]',
        "MAX_ALERTS_PER_RUN": "25",
        "ENVIRONMENT": "test",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_EC2_METADATA_DISABLED": "true",
    }
    for name, value in environment.items():
        monkeypatch.setenv(name, value)

    module_name = "flowlogs_detector_under_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, DETECTOR_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_query_covers_every_hour_and_exact_epoch(detector: Any) -> None:
    start = detector.datetime(2026, 7, 25, 23, 30, tzinfo=detector.timezone.utc)
    end = detector.datetime(2026, 7, 26, 0, 30, tzinfo=detector.timezone.utc)

    query = detector.build_exfil_query(start, end)

    assert "\"day\" = '25' AND \"hour\" = '23'" in query
    assert "\"day\" = '26' AND \"hour\" = '00'" in query
    assert f'AND "end" >= {int(start.timestamp())}' in query
    assert f'AND "end" < {int(end.timestamp())}' in query
    assert '"start" <' not in query
    assert "flow_direction = 'egress'" in query
    assert "COALESCE(NULLIF(pkt_dstaddr, '-'), dstaddr)" in query
    assert "203.0.113.0/24" in query


def test_query_aggregates_per_source_before_threshold(detector: Any) -> None:
    start = detector.datetime(2026, 7, 26, 8, 0, tzinfo=detector.timezone.utc)
    end = start + detector.timedelta(hours=1)

    query = detector.build_exfil_query(start, end)

    assert "GROUP BY account_id, instance_id, source_ip" in query
    assert "WHERE total_bytes > 1000" in query
    assert "max_by(destination_ip, destination_bytes)" in query
    assert "AS total_gib" in query
    assert "LIMIT 25" in query


def test_window_key_includes_configuration_fingerprint(detector: Any) -> None:
    start = detector.datetime(2026, 7, 26, 8, 0, tzinfo=detector.timezone.utc)
    end = start + detector.timedelta(hours=1)

    expected_material = (
        f"test:{start.isoformat()}:{end.isoformat()}:"
        f"{detector.DETECTOR_CONFIGURATION_FINGERPRINT}"
    )
    expected = detector.hashlib.sha256(expected_material.encode("utf-8")).hexdigest()

    assert detector._window_key(start, end) == expected


def test_get_query_results_handles_header_and_sparse_rows(
    detector: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pages = [
        {
            "ResultSet": {
                "ResultSetMetadata": {
                    "ColumnInfo": [{"Name": "account_id"}, {"Name": "total_bytes"}],
                },
                "Rows": [
                    {
                        "Data": [
                            {"VarCharValue": "account_id"},
                            {"VarCharValue": "total_bytes"},
                        ],
                    },
                    {"Data": [{"VarCharValue": "111122223333"}]},
                ],
            },
        },
    ]

    class FakePaginator:
        def paginate(self, **_: Any) -> list[dict[str, Any]]:
            return pages

    fake_athena = SimpleNamespace(
        get_paginator=lambda _: FakePaginator(),
    )
    monkeypatch.setattr(
        detector,
        "get_client",
        lambda service: fake_athena if service == "athena" else None,
    )

    assert detector.get_query_results("query-1") == [
        {"account_id": "111122223333", "total_bytes": ""},
    ]


def test_duplicate_window_skips_athena(
    detector: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(detector, "is_window_processed", lambda _: True)
    monkeypatch.setattr(
        detector,
        "start_query",
        lambda *_: pytest.fail("Athena should not run for a completed window"),
    )

    result = detector.lambda_handler(
        {"time": "2026-07-26T12:00:00Z"},
        SimpleNamespace(get_remaining_time_in_millis=lambda: 300000),
    )

    assert result["duplicateSkipped"] is True
    assert result["windowStart"] == "2026-07-26T10:45:00+00:00"
    assert result["windowEnd"] == "2026-07-26T11:45:00+00:00"


def test_successful_finding_is_published_then_marked(
    detector: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []
    findings = [{"account_id": "111122223333", "total_bytes": "2000"}]

    monkeypatch.setattr(detector, "is_window_processed", lambda _: False)
    monkeypatch.setattr(detector, "start_query", lambda *_: "query-1")
    monkeypatch.setattr(detector, "wait_for_query", lambda *_: None)
    monkeypatch.setattr(detector, "get_query_results", lambda _: findings)
    monkeypatch.setattr(
        detector,
        "publish_alert",
        lambda *_: calls.append("publish"),
    )
    monkeypatch.setattr(
        detector,
        "mark_window_processed",
        lambda *_args, **_kwargs: calls.append("mark"),
    )

    result = detector.lambda_handler(
        {"time": "2026-07-26T12:00:00Z"},
        SimpleNamespace(get_remaining_time_in_millis=lambda: 300000),
    )

    assert calls == ["publish", "mark"]
    assert result["findingCount"] == 1
    assert result["snsNotificationsPublished"] == 1


def test_publish_failure_does_not_mark_window(
    detector: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(detector, "is_window_processed", lambda _: False)
    monkeypatch.setattr(detector, "start_query", lambda *_: "query-1")
    monkeypatch.setattr(detector, "wait_for_query", lambda *_: None)
    monkeypatch.setattr(detector, "get_query_results", lambda _: [{"x": "y"}])
    monkeypatch.setattr(
        detector,
        "publish_alert",
        lambda *_: (_ for _ in ()).throw(RuntimeError("SNS unavailable")),
    )
    monkeypatch.setattr(
        detector,
        "mark_window_processed",
        lambda *_args, **_kwargs: pytest.fail("Failed runs must remain retryable"),
    )

    with pytest.raises(RuntimeError, match="SNS unavailable"):
        detector.lambda_handler(
            {"time": "2026-07-26T12:00:00Z"},
            SimpleNamespace(get_remaining_time_in_millis=lambda: 300000),
        )
