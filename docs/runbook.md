# Operational runbook

## Daily health

1. Confirm the EventBridge rule is enabled.
2. Check Lambda errors, throttles, duration, and invocation count.
3. Check visible DLQ messages and Athena failed queries/bytes scanned.
4. Sample the newest expected account/Region/hour prefixes.
5. Query `log_status` counts and investigate `SKIPDATA`.

## Alert triage

1. Record the alert window, query ID, account, instance, source, top
   destination, bytes, and destination count.
2. Confirm the finding is inside the stated window.
3. Identify ownership through inventory and the ENI/instance relationship.
4. Check whether NAT, proxy, firewall, or gateway processing changed attribution.
5. Enrich the destination with approved threat intelligence and business context.
6. Compare deployment, backup, replication, update, and export schedules.
7. Escalate through the incident process. This project does not isolate systems.

## Common failures

- `EXCEEDED_BYTES_SCANNED_LIMIT`: verify partitions and tune the cutoff only
  with evidence.
- `HIVE_PARTITION_SCHEMA_MISMATCH`: compare custom format and Glue schema.
- `AccessDenied`: find the exact API/resource in CloudTrail before widening IAM.
- Timeout: inspect Athena queue/execution time; Lambda stops near its deadline.
- Missing logs: check `DescribeFlowLogs`, bucket ARN format, `log_sources`, Hive
  prefix, KMS ARN encryption, and delivery delay.

For a DLQ alarm, preserve the message, correct the cause, reinvoke the original
payload, confirm DynamoDB completion, then delete the message.

## Tuning

Measure source-level hourly distributions, approved bulk transfers, NAT/proxy
concentration, late-delivery rate, bytes scanned, and analyst capacity. Record
the rationale for every threshold, exclusion, window, and delay change. Never
exclude a CIDR solely to suppress an unexplained alert.
