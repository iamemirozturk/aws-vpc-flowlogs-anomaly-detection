"""Scheduled VPC Flow Logs exfiltration detector.

The function queries a delayed record-end window in Athena, aggregates external
egress by source entity, publishes one bounded SNS notification, and records the
completed window and configuration in DynamoDB so replayed events are
idempotent.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import logging
import os
import re
import time
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ATHENA_DATABASE = os.environ["ATHENA_DATABASE"]
ATHENA_TABLE = os.environ.get("ATHENA_TABLE", "flow_logs")
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
ATHENA_RESULTS_BUCKET = os.environ["ATHENA_RESULTS_BUCKET"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
DETECTION_STATE_TABLE = os.environ["DETECTION_STATE_TABLE"]
EXFIL_THRESHOLD_BYTES = int(os.environ["EXFIL_THRESHOLD_BYTES"])
DETECTION_WINDOW_MINUTES = int(os.environ.get("DETECTION_WINDOW_MINUTES", "60"))
DATA_DELAY_MINUTES = int(os.environ.get("DATA_DELAY_MINUTES", "15"))
MAX_ALERTS_PER_RUN = int(os.environ.get("MAX_ALERTS_PER_RUN", "25"))
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")

POLL_INTERVAL_SECONDS = 2
MAX_POLL_ATTEMPTS = 150
STATE_TTL_DAYS = 7

PRIVATE_DESTINATION_CIDRS = (
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "::1/128",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8",
)


def _load_excluded_cidrs() -> tuple[str, ...]:
    """Validate and normalize deployment-supplied CIDR exclusions."""
    raw_cidrs = json.loads(os.environ.get("EXCLUDED_DESTINATION_CIDRS", "[]"))
    if not isinstance(raw_cidrs, list):
        raise ValueError("EXCLUDED_DESTINATION_CIDRS must encode a JSON list")
    normalized = [str(ipaddress.ip_network(cidr, strict=False)) for cidr in raw_cidrs]
    return tuple(dict.fromkeys((*PRIVATE_DESTINATION_CIDRS, *normalized)))


EXCLUDED_DESTINATION_CIDRS = _load_excluded_cidrs()
DETECTOR_CONFIGURATION_FINGERPRINT = hashlib.sha256(
    json.dumps(
        {
            "athena_database": ATHENA_DATABASE,
            "athena_table": ATHENA_TABLE,
            "athena_workgroup": ATHENA_WORKGROUP,
            "threshold_bytes": EXFIL_THRESHOLD_BYTES,
            "window_minutes": DETECTION_WINDOW_MINUTES,
            "data_delay_minutes": DATA_DELAY_MINUTES,
            "max_alerts_per_run": MAX_ALERTS_PER_RUN,
            "excluded_destination_cidrs": EXCLUDED_DESTINATION_CIDRS,
        },
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8"),
).hexdigest()


def _validate_configuration() -> None:
    """Fail fast on unsafe identifiers or invalid numeric configuration."""
    identifier_pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
    if not identifier_pattern.fullmatch(ATHENA_DATABASE):
        raise ValueError("ATHENA_DATABASE is not a valid unqualified identifier")
    if not identifier_pattern.fullmatch(ATHENA_TABLE):
        raise ValueError("ATHENA_TABLE is not a valid unqualified identifier")
    if EXFIL_THRESHOLD_BYTES <= 0:
        raise ValueError("EXFIL_THRESHOLD_BYTES must be positive")
    if not 5 <= DETECTION_WINDOW_MINUTES <= 1440:
        raise ValueError("DETECTION_WINDOW_MINUTES must be between 5 and 1440")
    if not 0 <= DATA_DELAY_MINUTES <= 180:
        raise ValueError("DATA_DELAY_MINUTES must be between 0 and 180")
    if not 1 <= MAX_ALERTS_PER_RUN <= 100:
        raise ValueError("MAX_ALERTS_PER_RUN must be between 1 and 100")


_validate_configuration()


@lru_cache(maxsize=None)
def get_client(service_name: str) -> Any:
    """Return a cached boto3 client; kept behind a function for unit testing."""
    return boto3.client(service_name)


def _hour_partitions(
    window_start: datetime,
    window_end: datetime,
) -> list[datetime]:
    """Return every UTC hour touched by the half-open query window."""
    current = window_start.replace(minute=0, second=0, microsecond=0)
    final = (window_end - timedelta(microseconds=1)).replace(
        minute=0,
        second=0,
        microsecond=0,
    )
    partitions: list[datetime] = []
    while current <= final:
        partitions.append(current)
        current += timedelta(hours=1)
    return partitions


def _partition_predicate(
    window_start: datetime,
    window_end: datetime,
) -> str:
    predicates = [
        (
            f"(\"year\" = '{hour:%Y}' AND \"month\" = '{hour:%m}' "
            f"AND \"day\" = '{hour:%d}' AND \"hour\" = '{hour:%H}')"
        )
        for hour in _hour_partitions(window_start, window_end)
    ]
    return "\n        OR ".join(predicates)


def _excluded_cidr_predicate() -> str:
    address = "TRY_CAST(effective_dstaddr AS IPADDRESS)"
    conditions = [
        f"contains(CAST('{cidr}' AS IPPREFIX), {address})"
        for cidr in EXCLUDED_DESTINATION_CIDRS
    ]
    return "\n        OR ".join(conditions)


def build_exfil_query(
    window_start: datetime,
    window_end: datetime,
) -> str:
    """Build a partition-pruned query for accepted external egress."""
    if window_start.tzinfo is None or window_end.tzinfo is None:
        raise ValueError("Query window datetimes must be timezone-aware")
    if window_start >= window_end:
        raise ValueError("window_start must precede window_end")

    start_epoch = int(window_start.timestamp())
    end_epoch = int(window_end.timestamp())
    partitions = _partition_predicate(window_start, window_end)
    cidr_exclusions = _excluded_cidr_predicate()

    return f"""
WITH normalized AS (
    SELECT
        account_id,
        COALESCE(NULLIF(instance_id, '-'), 'unknown') AS instance_id,
        COALESCE(NULLIF(pkt_srcaddr, '-'), srcaddr) AS effective_srcaddr,
        COALESCE(NULLIF(pkt_dstaddr, '-'), dstaddr) AS effective_dstaddr,
        bytes,
        packets
    FROM "{ATHENA_DATABASE}"."{ATHENA_TABLE}"
    WHERE (
        {partitions}
    )
      AND "end" >= {start_epoch}
      AND "end" < {end_epoch}
      AND action = 'ACCEPT'
      AND flow_direction = 'egress'
      AND log_status = 'OK'
),
destination_totals AS (
    SELECT
        account_id,
        instance_id,
        effective_srcaddr AS source_ip,
        effective_dstaddr AS destination_ip,
        SUM(bytes) AS destination_bytes,
        SUM(packets) AS destination_packets,
        COUNT(*) AS destination_records
    FROM normalized
    WHERE effective_srcaddr IS NOT NULL
      AND effective_dstaddr IS NOT NULL
      AND effective_dstaddr <> '-'
      AND TRY_CAST(effective_dstaddr AS IPADDRESS) IS NOT NULL
      AND NOT (
        {cidr_exclusions}
      )
    GROUP BY account_id, instance_id, effective_srcaddr, effective_dstaddr
),
entity_totals AS (
    SELECT
        account_id,
        instance_id,
        source_ip,
        max_by(destination_ip, destination_bytes) AS top_destination_ip,
        COUNT(*) AS unique_destinations,
        SUM(destination_bytes) AS total_bytes,
        SUM(destination_packets) AS total_packets,
        SUM(destination_records) AS flow_records
    FROM destination_totals
    GROUP BY account_id, instance_id, source_ip
)
SELECT
    account_id,
    instance_id,
    source_ip,
    top_destination_ip,
    unique_destinations,
    total_bytes,
    ROUND(total_bytes / 1073741824.0, 2) AS total_gib,
    total_packets,
    flow_records
FROM entity_totals
WHERE total_bytes > {EXFIL_THRESHOLD_BYTES}
ORDER BY total_bytes DESC
LIMIT {MAX_ALERTS_PER_RUN}
""".strip()


def start_query(sql: str, window_key: str) -> str:
    """Start an Athena query with a deterministic idempotency token."""
    client_token = hashlib.sha256(
        f"{window_key}:{sql}".encode("utf-8"),
    ).hexdigest()
    response = get_client("athena").start_query_execution(
        QueryString=sql,
        ClientRequestToken=client_token,
        QueryExecutionContext={"Database": ATHENA_DATABASE},
        WorkGroup=ATHENA_WORKGROUP,
        ResultConfiguration={"OutputLocation": ATHENA_RESULTS_BUCKET},
    )
    query_id = response["QueryExecutionId"]
    logger.info("Started Athena query query_id=%s window_key=%s", query_id, window_key)
    return query_id


def wait_for_query(query_id: str, context: Any = None) -> None:
    """Wait for Athena, stopping the query before Lambda runs out of time."""
    athena = get_client("athena")
    for attempt in range(1, MAX_POLL_ATTEMPTS + 1):
        result = athena.get_query_execution(QueryExecutionId=query_id)
        status = result["QueryExecution"]["Status"]
        state = status["State"]
        logger.info(
            "Athena query status query_id=%s state=%s attempt=%d",
            query_id,
            state,
            attempt,
        )

        if state == "SUCCEEDED":
            return
        if state in {"FAILED", "CANCELLED"}:
            reason = status.get("StateChangeReason", "No reason returned")
            raise RuntimeError(f"Athena query {query_id} {state}: {reason}")

        if (
            context is not None
            and context.get_remaining_time_in_millis() < 15000
        ):
            athena.stop_query_execution(QueryExecutionId=query_id)
            raise TimeoutError(f"Stopped Athena query {query_id} before Lambda timeout")

        time.sleep(POLL_INTERVAL_SECONDS)

    athena.stop_query_execution(QueryExecutionId=query_id)
    raise TimeoutError(
        f"Athena query {query_id} exceeded {MAX_POLL_ATTEMPTS} polls",
    )


def get_query_results(query_id: str) -> list[dict[str, str]]:
    """Return all Athena data rows as dictionaries, excluding the header."""
    paginator = get_client("athena").get_paginator("get_query_results")
    records: list[dict[str, str]] = []
    first_page = True

    for page in paginator.paginate(QueryExecutionId=query_id):
        column_info = page["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]
        column_names = [column["Name"] for column in column_info]
        result_rows = page["ResultSet"].get("Rows", [])

        if first_page and result_rows:
            possible_header = [
                cell.get("VarCharValue", "")
                for cell in result_rows[0].get("Data", [])
            ]
            if possible_header == column_names:
                result_rows = result_rows[1:]
            first_page = False

        for result_row in result_rows:
            values = [
                cell.get("VarCharValue", "")
                for cell in result_row.get("Data", [])
            ]
            values.extend([""] * (len(column_names) - len(values)))
            records.append(dict(zip(column_names, values)))

    return records


def _window_key(window_start: datetime, window_end: datetime) -> str:
    key_material = (
        f"{ENVIRONMENT}:{window_start.isoformat()}:{window_end.isoformat()}:"
        f"{DETECTOR_CONFIGURATION_FINGERPRINT}"
    )
    return hashlib.sha256(key_material.encode("utf-8")).hexdigest()


def is_window_processed(window_key: str) -> bool:
    """Check whether this exact detection window completed successfully."""
    response = get_client("dynamodb").get_item(
        TableName=DETECTION_STATE_TABLE,
        Key={"detection_key": {"S": window_key}},
        ConsistentRead=True,
    )
    return "Item" in response


def mark_window_processed(
    window_key: str,
    window_end: datetime,
    query_id: str,
    alert_count: int,
) -> None:
    """Record a completed window with a short TTL."""
    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(days=STATE_TTL_DAYS)).timestamp(),
    )
    get_client("dynamodb").put_item(
        TableName=DETECTION_STATE_TABLE,
        Item={
            "detection_key": {"S": window_key},
            "window_end": {"S": window_end.isoformat()},
            "query_id": {"S": query_id},
            "alert_count": {"N": str(alert_count)},
            "expires_at": {"N": str(expires_at)},
        },
    )


def publish_alert(
    rows: list[dict[str, str]],
    query_id: str,
    window_start: datetime,
    window_end: datetime,
) -> None:
    """Publish one bounded notification for all entities over threshold."""
    payload = {
        "schema_version": "1.0",
        "alert_type": "POTENTIAL_DATA_EXFILTRATION",
        "severity": "HIGH",
        "environment": ENVIRONMENT,
        "window_start": window_start.isoformat(),
        "window_end": window_end.isoformat(),
        "threshold_bytes": EXFIL_THRESHOLD_BYTES,
        "athena_query_id": query_id,
        "finding_count": len(rows),
        "findings": rows,
    }
    subject = (
        f"[{ENVIRONMENT.upper()}] Flow Logs exfiltration findings: {len(rows)}"
    )
    get_client("sns").publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=json.dumps(payload, indent=2, sort_keys=True),
        MessageAttributes={
            "alert_type": {
                "DataType": "String",
                "StringValue": "POTENTIAL_DATA_EXFILTRATION",
            },
            "severity": {
                "DataType": "String",
                "StringValue": "HIGH",
            },
        },
    )
    logger.info(
        "Published SNS notification query_id=%s finding_count=%d",
        query_id,
        len(rows),
    )


def _event_time(event: dict[str, Any]) -> datetime:
    event_timestamp = event.get("time")
    if not event_timestamp:
        return datetime.now(timezone.utc).replace(microsecond=0)
    parsed = datetime.fromisoformat(str(event_timestamp).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("EventBridge time must include a timezone")
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Run one deterministic detection window."""
    anchor = _event_time(event)
    window_end = anchor - timedelta(minutes=DATA_DELAY_MINUTES)
    window_start = window_end - timedelta(minutes=DETECTION_WINDOW_MINUTES)
    window_key = _window_key(window_start, window_end)

    logger.info(
        "Starting detection window_key=%s window_start=%s window_end=%s "
        "threshold_bytes=%d",
        window_key,
        window_start.isoformat(),
        window_end.isoformat(),
        EXFIL_THRESHOLD_BYTES,
    )

    if is_window_processed(window_key):
        logger.info("Skipping previously completed window window_key=%s", window_key)
        return {
            "statusCode": 200,
            "duplicateSkipped": True,
            "windowKey": window_key,
            "windowStart": window_start.isoformat(),
            "windowEnd": window_end.isoformat(),
        }

    sql = build_exfil_query(window_start, window_end)
    query_id = start_query(sql, window_key)
    wait_for_query(query_id, context)
    rows = get_query_results(query_id)

    if rows:
        publish_alert(rows, query_id, window_start, window_end)

    mark_window_processed(
        window_key,
        window_end,
        query_id,
        alert_count=len(rows),
    )
    logger.info(
        "Completed detection query_id=%s finding_count=%d",
        query_id,
        len(rows),
    )

    return {
        "statusCode": 200,
        "duplicateSkipped": False,
        "queryId": query_id,
        "findingCount": len(rows),
        "snsNotificationsPublished": 1 if rows else 0,
        "windowKey": window_key,
        "windowStart": window_start.isoformat(),
        "windowEnd": window_end.isoformat(),
    }
