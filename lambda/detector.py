"""
VPC Flow Logs Anomaly Detector
-------------------------------
Scheduled Lambda function that:
1. Builds a time-windowed Athena query for high-volume outbound traffic
2. Polls Athena until the query completes
3. Evaluates each result row against the configured threshold
4. Publishes a structured SNS alert for every threshold breach
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Environment configuration
# ---------------------------------------------------------------------------
ATHENA_DATABASE       = os.environ["ATHENA_DATABASE"]
ATHENA_WORKGROUP      = os.environ["ATHENA_WORKGROUP"]
ATHENA_RESULTS_BUCKET = os.environ["ATHENA_RESULTS_BUCKET"]
SNS_TOPIC_ARN         = os.environ["SNS_TOPIC_ARN"]
EXFIL_THRESHOLD_BYTES = int(os.environ["EXFIL_THRESHOLD_BYTES"])
ENVIRONMENT           = os.environ.get("ENVIRONMENT", "prod")

# Athena polling
POLL_INTERVAL_SECONDS = 5
MAX_POLL_ATTEMPTS     = 60   # 5 min max wait

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
athena = boto3.client("athena")
sns    = boto3.client("sns")


# ---------------------------------------------------------------------------
# Query builder
# ---------------------------------------------------------------------------
def build_exfil_query(year: str, month: str, day: str) -> str:
    """
    Returns a partitioned Athena query that aggregates outbound bytes per
    instance/srcaddr/dstaddr, filtering to traffic destined outside RFC-1918
    ranges and above the configured threshold.
    """
    threshold = EXFIL_THRESHOLD_BYTES
    return f"""
SELECT
    account_id,
    instance_id,
    srcaddr,
    dstaddr,
    SUM(bytes)  AS total_bytes,
    SUM(bytes) / 1073741824.0 AS total_gb,
    COUNT(*)    AS flow_records
FROM "{ATHENA_DATABASE}"."flow_logs"
WHERE year  = '{year}'
  AND month = '{month}'
  AND day   = '{day}'
  AND action = 'ACCEPT'
  -- Exclude RFC-1918 destinations (internal traffic)
  AND dstaddr NOT LIKE '10.%'
  AND dstaddr NOT LIKE '172.16.%'
  AND dstaddr NOT LIKE '172.17.%'
  AND dstaddr NOT LIKE '172.18.%'
  AND dstaddr NOT LIKE '172.19.%'
  AND dstaddr NOT LIKE '172.20.%'
  AND dstaddr NOT LIKE '172.21.%'
  AND dstaddr NOT LIKE '172.22.%'
  AND dstaddr NOT LIKE '172.23.%'
  AND dstaddr NOT LIKE '172.24.%'
  AND dstaddr NOT LIKE '172.25.%'
  AND dstaddr NOT LIKE '172.26.%'
  AND dstaddr NOT LIKE '172.27.%'
  AND dstaddr NOT LIKE '172.28.%'
  AND dstaddr NOT LIKE '172.29.%'
  AND dstaddr NOT LIKE '172.30.%'
  AND dstaddr NOT LIKE '172.31.%'
  AND dstaddr NOT LIKE '192.168.%'
  -- Exclude loopback and link-local
  AND dstaddr NOT LIKE '127.%'
  AND dstaddr NOT LIKE '169.254.%'
GROUP BY account_id, instance_id, srcaddr, dstaddr
HAVING SUM(bytes) > {threshold}
ORDER BY total_bytes DESC
LIMIT 100;
"""


# ---------------------------------------------------------------------------
# Athena helpers
# ---------------------------------------------------------------------------
def start_query(sql: str) -> str:
    response = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": ATHENA_DATABASE},
        WorkGroup=ATHENA_WORKGROUP,
        ResultConfiguration={"OutputLocation": ATHENA_RESULTS_BUCKET},
    )
    query_id = response["QueryExecutionId"]
    logger.info("Started Athena query: %s", query_id)
    return query_id


def wait_for_query(query_id: str) -> str:
    """Polls until SUCCEEDED / FAILED / CANCELLED. Returns final state."""
    terminal_states = {"SUCCEEDED", "FAILED", "CANCELLED"}
    for attempt in range(MAX_POLL_ATTEMPTS):
        result = athena.get_query_execution(QueryExecutionId=query_id)
        state  = result["QueryExecution"]["Status"]["State"]
        logger.info("Query %s — state: %s (attempt %d)", query_id, state, attempt + 1)
        if state in terminal_states:
            if state != "SUCCEEDED":
                reason = result["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
                raise RuntimeError(f"Athena query {query_id} {state}: {reason}")
            return state
        time.sleep(POLL_INTERVAL_SECONDS)
    raise TimeoutError(f"Athena query {query_id} did not complete after {MAX_POLL_ATTEMPTS} polls")


def get_query_results(query_id: str) -> list[dict[str, Any]]:
    """Returns query result rows as a list of dicts (skips header row)."""
    rows: list[dict[str, Any]] = []
    paginator = athena.get_paginator("get_query_results")
    first_page = True

    for page in paginator.paginate(QueryExecutionId=query_id):
        result_rows = page["ResultSet"]["Rows"]
        if first_page:
            columns = [col["VarCharValue"] for col in result_rows[0]["Data"]]
            result_rows = result_rows[1:]
            first_page = False

        for row in result_rows:
            values = [cell.get("VarCharValue", "") for cell in row["Data"]]
            rows.append(dict(zip(columns, values)))

    return rows


# ---------------------------------------------------------------------------
# Alert publisher
# ---------------------------------------------------------------------------
def publish_alert(row: dict[str, Any], query_id: str, detection_timestamp: str) -> None:
    payload = {
        "alert_type":        "POTENTIAL_DATA_EXFILTRATION",
        "severity":          "HIGH",
        "environment":       ENVIRONMENT,
        "account_id":        row.get("account_id", "unknown"),
        "instance_id":       row.get("instance_id", "unknown"),
        "source_ip":         row.get("srcaddr", "unknown"),
        "destination_ip":    row.get("dstaddr", "unknown"),
        "total_bytes":       row.get("total_bytes", "0"),
        "total_gb":          row.get("total_gb", "0"),
        "flow_records":      row.get("flow_records", "0"),
        "threshold_bytes":   str(EXFIL_THRESHOLD_BYTES),
        "threshold_gb":      str(round(EXFIL_THRESHOLD_BYTES / (1024 ** 3), 2)),
        "detection_window":  "last_1_day_partition",
        "timestamp":         detection_timestamp,
        "athena_query_id":   query_id,
    }

    message = (
        f"🚨 POTENTIAL DATA EXFILTRATION DETECTED\n\n"
        f"Account:        {payload['account_id']}\n"
        f"Instance:       {payload['instance_id']}\n"
        f"Source IP:      {payload['source_ip']}\n"
        f"Destination IP: {payload['destination_ip']}\n"
        f"Total Bytes:    {payload['total_bytes']} ({payload['total_gb']} GB)\n"
        f"Threshold:      {payload['threshold_gb']} GB\n"
        f"Detected At:    {payload['timestamp']}\n"
        f"Athena Query:   {payload['athena_query_id']}\n\n"
        f"Full payload:\n{json.dumps(payload, indent=2)}"
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[{ENVIRONMENT.upper()}] Data Exfiltration Alert — {payload['account_id']} / {payload['instance_id']}",
        Message=message,
        MessageAttributes={
            "alert_type": {
                "DataType":    "String",
                "StringValue": "POTENTIAL_DATA_EXFILTRATION",
            },
            "severity": {
                "DataType":    "String",
                "StringValue": "HIGH",
            },
        },
    )
    logger.info(
        "Published alert for instance=%s src=%s dst=%s bytes=%s",
        payload["instance_id"], payload["source_ip"],
        payload["destination_ip"], payload["total_bytes"],
    )


# ---------------------------------------------------------------------------
# Lambda handler
# ---------------------------------------------------------------------------
def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    now               = datetime.now(timezone.utc)
    detection_ts      = now.isoformat()
    year  = now.strftime("%Y")
    month = now.strftime("%m")
    day   = now.strftime("%d")

    logger.info(
        "Starting anomaly detection for partition year=%s month=%s day=%s threshold=%d bytes",
        year, month, day, EXFIL_THRESHOLD_BYTES,
    )

    sql      = build_exfil_query(year, month, day)
    query_id = start_query(sql)
    wait_for_query(query_id)
    rows     = get_query_results(query_id)

    logger.info("Query returned %d rows above threshold", len(rows))

    alerts_published = 0
    for row in rows:
        try:
            publish_alert(row, query_id, detection_ts)
            alerts_published += 1
        except Exception as exc:
            logger.error("Failed to publish alert for row %s: %s", row, exc)

    return {
        "statusCode":       200,
        "queryId":          query_id,
        "rowsEvaluated":    len(rows),
        "alertsPublished":  alerts_published,
        "detectionTs":      detection_ts,
    }
