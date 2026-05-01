# Architecture Deep Dive

## Overview

This document provides a detailed explanation of each component in the VPC Flow Logs Centralized Anomaly Detection Platform and the design decisions behind them.

---

## 1. Multi-Account Strategy

The solution follows the AWS Organizations pattern of separating workloads into **spoke accounts** and centralizing security tooling into a dedicated **Security/Logging account**.

```
AWS Organizations
├── Management Account
├── Security OU
│   └── Security/Logging Account  ← Central bucket lives here
├── Production OU
│   ├── App Account A             ← Spoke: VPC-A, VPC-B
│   └── App Account B             ← Spoke: VPC-C
└── Staging OU
    └── App Account C             ← Spoke: VPC-D
```

**Why this matters:**
- Spoke accounts cannot delete or tamper with logs (separate account boundary)
- Security team has unified visibility without needing access to each spoke account
- IAM permissions are scoped — spoke delivery roles can only `PutObject` to their prefix

---

## 2. Log Ingestion Layer

### VPC Flow Log Format

The solution configures an **enriched flow log format** that includes fields not present in the AWS default:

| Field | Purpose |
|---|---|
| `instance-id` | Attribute traffic to a specific EC2 instance |
| `vpc-id` | Identify the originating VPC |
| `subnet-id` | Granular subnet attribution |
| `flow-direction` | Distinguish ingress vs egress |
| `pkt-src-aws-service` | Identify AWS service as traffic source |
| `pkt-dst-aws-service` | Identify AWS service as traffic destination |
| `tcp-flags` | Enable TCP connection state analysis |

### Parquet Format with Hive Partitioning

Logs are stored as **Apache Parquet** files with Hive-compatible partition paths:

```
s3://central-logs/AWSLogs/
  {account-id}/
    vpcflowlogs/
      {region}/
        {year}/
          {month}/
            {day}/
              {hour}/
                *.parquet
```

Parquet over plain-text provides:
- ~4x smaller file size (columnar compression)
- Athena reads only relevant columns → lower cost
- Native type support (timestamps, integers) without casting

---

## 3. Schema Management — Glue Crawler

The Glue Crawler is configured with `CRAWL_NEW_FOLDERS_ONLY` to avoid re-processing already-catalogued data. This reduces Glue DPU-hours consumed per run.

**Partition Discovery:** The crawler automatically discovers year/month/day/hour partitions and registers them in the Glue Catalog, enabling Athena partition pruning.

**Optimization Path:** The repo includes migration guidance to **Athena Partition Projection**, which eliminates the Glue Crawler entirely by declaring partition ranges at query time — recommended for stable, predictable partition schemes.

---

## 4. Detection Logic

### Threshold Model

The detector uses a **bytes-aggregated, time-windowed** model:

```
FOR EACH (account_id, instance_id, srcaddr, dstaddr):
  IF SUM(bytes) WHERE action=ACCEPT AND dst ∉ RFC-1918 > threshold:
    ALERT
```

The RFC-1918 exclusion filters out:
- `10.0.0.0/8` — Internal VPC traffic
- `172.16.0.0/12` — Private subnets (Transit Gateway, VPN)
- `192.168.0.0/16` — On-premises via Direct Connect / VPN
- `127.x.x.x` — Loopback
- `169.254.x.x` — Link-local / EC2 metadata service

### False Positive Reduction

To reduce noise, consider these tuning strategies (configurable via variables):

1. **AWS Service exclusions** — Use `pkt_dst_aws_service` to exclude known S3/CloudFront egress
2. **Trusted CIDR allowlisting** — Additional SQL conditions per deployment
3. **Per-instance thresholds** — Future roadmap item using DynamoDB config table
4. **Time-of-day context** — Flag overnight spikes that differ from business-hours baselines

---

## 5. Cost Architecture

### Athena Cost Control

The Athena Workgroup enforces a `bytes_scanned_cutoff_per_query` of 10 GB, preventing runaway queries. Combined with partition pruning, typical detection queries scan only the current day's partition (~100 MB–5 GB depending on environment size).

**Cost formula:**
```
Athena cost = (bytes_scanned / 1TB) × $5.00
With daily partition (~1 GB scanned): $0.005 per query
At hourly detection (720 queries/month): ~$3.60/month
```

### Glue Crawler Cost

Each crawler run uses approximately 1 DPU-hour at `$0.44/DPU-hour`. Daily scheduling = `~$13.20/month`. Switching to Partition Projection eliminates this cost entirely.

---

## 6. Security Controls

### Bucket Policy Defense in Depth

The central bucket policy enforces three controls simultaneously:
1. **`aws:SecureTransport`** — All `s3:*` denied over HTTP
2. **`aws:SourceAccount`** — `PutObject` allowed only from enrolled spoke account IDs
3. **`s3:x-amz-acl: bucket-owner-full-control`** — Prevents spoke accounts from retaining object ownership

### Object Lock

S3 Object Lock in **COMPLIANCE mode** prevents even the bucket owner (root user) from deleting or overwriting logs during the retention period. This satisfies regulatory requirements for log immutability (SOC 2 CC7.2, NIST 800-53 AU-9).

---

## 7. Observability

| Signal | Where |
|---|---|
| Lambda invocations & errors | CloudWatch Metrics (auto) |
| Lambda execution logs | CloudWatch Logs `/aws/lambda/prod-flowlogs-detector` |
| Athena query history | Athena query history + CloudWatch Metrics |
| Glue Crawler job history | AWS Glue console + CloudWatch |
| S3 access patterns | S3 server access logs → access logs bucket |

---

## 8. Evolution Path

```
Phase 1 (This Repo)          Phase 2                    Phase 3
─────────────────────        ─────────────────────────  ─────────────────────────
Glue Crawler                 Partition Projection        ML-based anomaly (SageMaker)
SQL threshold detection  →   Per-instance thresholds  → Behavioral baselines
SNS email alerts             Slack / PagerDuty           SIEM integration (Splunk)
Manual spoke onboarding      AWS Orgs auto-onboarding    QuickSight dashboard
```
