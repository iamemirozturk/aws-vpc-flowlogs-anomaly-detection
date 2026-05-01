# 🔍 AWS VPC Flow Logs — Centralized Anomaly Detection Platform

<p align="center">
  <img src="docs/architecture.png" alt="Architecture Diagram" width="860"/>
</p>

<p align="center">
  <a href="https://www.terraform.io/"><img src="https://img.shields.io/badge/Terraform-1.6+-7B42BC?style=flat&logo=terraform" /></a>
  <a href="https://aws.amazon.com/"><img src="https://img.shields.io/badge/AWS-Multi--Account-FF9900?style=flat&logo=amazon-aws" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-green.svg" /></a>
  <a href="https://github.com/your-handle/aws-vpc-flowlogs-anomaly-detection/actions"><img src="https://img.shields.io/badge/CI-Terraform%20Validate-blue?logo=github-actions" /></a>
  <img src="https://img.shields.io/badge/Security-tfsec%20%7C%20Checkov-critical" />
  <img src="https://img.shields.io/badge/CIS-AWS%20Foundations%20v1.5-blue" />
</p>

---

## 📌 Overview

This project implements a **centralized, multi-account network traffic visibility and anomaly detection platform** on AWS. It aggregates VPC Flow Logs from multiple spoke accounts into a central Security/Logging account, enabling SQL-based analysis via Amazon Athena and automated alerting via Lambda + SNS.

**Primary use cases:**
- 🚨 Detect potential **data exfiltration** (outbound traffic spikes > configurable threshold)
- 🔎 Perform **cross-account traffic analysis** without complex cross-account queries
- 📊 Generate **compliance and audit reports** for specific instances, VPCs, or date ranges
- 💰 Gain **cost visibility** by attributing data transfer to specific workloads

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SPOKE ACCOUNTS (N)                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │  VPC-A   │  │  VPC-B   │  │  VPC-C   │  │  IAM Cross-Acct  │   │
│  │Flow Logs │  │Flow Logs │  │Flow Logs │  │  Delivery Role   │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────────────┘   │
└───────┼──────────────┼─────────────┼────────────────────────────────┘
        │              │             │   (Cross-Account S3 Delivery)
        ▼              ▼             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    SECURITY / LOGGING ACCOUNT                       │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              S3 Central Log Bucket                          │   │
│  │  s3://central-logs/AWSLogs/{account}/{vpc}/{year}/{month}/  │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                   │
│          ┌──────────────────────┼─────────────────┐                │
│          ▼                      ▼                  ▼                │
│  ┌──────────────┐    ┌─────────────────┐   ┌────────────────┐      │
│  │  AWS Glue    │    │  Amazon Athena  │   │  EventBridge   │      │
│  │  Crawler     │───▶│  (SQL Queries)  │◀──│  (Schedule)    │      │
│  │  (Scheduled) │    │  Glue Catalog   │   └───────┬────────┘      │
│  └──────────────┘    └────────┬────────┘           │               │
│                               │              ┌──────▼──────┐        │
│                               │              │   Lambda    │        │
│                               └─────────────▶│  Detector   │        │
│                                              └──────┬──────┘        │
│                                                     │               │
│                                              ┌──────▼──────┐        │
│                                              │  Amazon SNS │        │
│                                              │  (Alerts)   │        │
│                                              └─────────────┘        │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|---|---|
| **S3 over CloudWatch for log delivery** | Up to 80% lower ingestion cost at scale |
| **Glue Crawler + Athena** | Serverless, schema-on-read, no ETL pipeline needed |
| **Partition pruning (year/month/day)** | Prevents full table scans; controls Athena query costs |
| **Lambda threshold detection** | Transforms passive analytics into active alerting |
| **SNS for alerting** | Flexible fan-out: email, PagerDuty, Slack, SIEM |
| **Centralized logging account** | Separation of concerns; spoke accounts can't tamper with logs |

---

## 🧩 Module Structure

```
.
├── modules/
│   ├── central-logging/        # S3 bucket, Glue DB, Athena workgroup, KMS
│   ├── spoke-account/          # VPC Flow Log enablement + cross-account IAM role
│   └── detection-engine/       # Lambda, EventBridge rule, SNS topic
├── lambda/
│   └── detector.py             # Anomaly detection logic
├── athena/
│   └── queries/
│       ├── top_talkers.sql
│       ├── exfil_detection.sql
│       ├── cross_account_summary.sql
│       └── instance_traffic_report.sql
├── examples/
│   ├── single-account/         # Quick start for single-account testing
│   └── multi-account/          # Full org-wide deployment
├── docs/
│   ├── architecture.md
│   ├── architecture.drawio
│   └── architecture.png
├── .github/workflows/
│   ├── terraform-ci.yml
│   └── security-scan.yml
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
└── versions.tf
```

---

## 🚀 Prerequisites

| Requirement | Version / Notes |
|---|---|
| Terraform | `>= 1.6` |
| AWS CLI | `>= 2.x`, configured with appropriate profiles |
| Python | `>= 3.11` (for Lambda) |
| tfsec | Latest (optional, for local security scanning) |
| checkov | Latest (optional, for local policy checks) |

### AWS Permissions Required

**Central (Security/Logging) Account:**
- `s3:*` on the central log bucket
- `glue:*` on the Flow Logs database
- `athena:*` on the designated workgroup
- `lambda:*` for the detection engine
- `sns:*` for alerting
- `kms:*` for log encryption

**Spoke Accounts:**
- `ec2:CreateFlowLogs` and `ec2:DescribeVpcs`
- `iam:CreateRole` / `iam:AttachRolePolicy` for the delivery role
- Cross-account `s3:PutObject` to the central bucket

---

## ⚙️ Quick Start

### 1 — Clone & configure

```bash
git clone https://github.com/iamemirozturk/aws-vpc-flowlogs-anomaly-detection.git
cd aws-vpc-flowlogs-anomaly-detection
cp examples/multi-account/terraform.tfvars.example terraform.tfvars
```

### 2 — Edit `terraform.tfvars`

```hcl
# Central logging account
central_account_id   = "111122223333"
central_region       = "us-east-1"
log_bucket_name      = "org-central-vpc-flowlogs"

# Spoke accounts to onboard
spoke_accounts = [
  { account_id = "444455556666", vpc_ids = ["vpc-aaaa1111", "vpc-bbbb2222"] },
  { account_id = "777788889999", vpc_ids = ["vpc-cccc3333"] },
]

# Anomaly detection thresholds
exfil_threshold_bytes = 53687091200   # 50 GB
alert_email           = "security-team@example.com"
detection_schedule    = "rate(1 hour)"
```

### 3 — Deploy central account resources

```bash
export AWS_PROFILE=central-account

terraform init
terraform workspace new central
terraform plan -target=module.central_logging
terraform apply -target=module.central_logging
```

### 4 — Deploy spoke account resources

```bash
# Repeat per spoke account
export AWS_PROFILE=spoke-account-1

terraform workspace new spoke-444455556666
terraform plan -target=module.spoke_account["444455556666"]
terraform apply -target=module.spoke_account["444455556666"]
```

### 5 — Deploy detection engine

```bash
export AWS_PROFILE=central-account

terraform plan -target=module.detection_engine
terraform apply -target=module.detection_engine
```

---

## 🔍 Sample Athena Queries

### Top Talkers (last 24h)

```sql
SELECT
  instance_id,
  srcaddr,
  dstaddr,
  SUM(bytes) AS total_bytes,
  SUM(bytes) / 1073741824.0 AS total_gb
FROM vpc_flow_logs.flow_logs
WHERE year  = '2024'
  AND month = '01'
  AND day   = '15'
  AND action = 'ACCEPT'
GROUP BY instance_id, srcaddr, dstaddr
ORDER BY total_bytes DESC
LIMIT 50;
```

### Potential Exfiltration Detection

```sql
SELECT
  account_id,
  instance_id,
  srcaddr,
  dstaddr,
  SUM(bytes) AS total_bytes
FROM vpc_flow_logs.flow_logs
WHERE year  = '2024'
  AND month = '01'
  AND dstaddr NOT LIKE '10.%'
  AND dstaddr NOT LIKE '172.16.%'
  AND dstaddr NOT LIKE '192.168.%'
  AND action = 'ACCEPT'
GROUP BY account_id, instance_id, srcaddr, dstaddr
HAVING SUM(bytes) > 53687091200  -- 50 GB
ORDER BY total_bytes DESC;
```

---

## 🚨 Alert Format

When a threshold is exceeded, an SNS notification is sent with the following payload:

```json
{
  "alert_type": "POTENTIAL_DATA_EXFILTRATION",
  "severity": "HIGH",
  "account_id": "444455556666",
  "instance_id": "i-0abc123def456789",
  "source_ip": "10.0.1.42",
  "destination_ip": "203.0.113.99",
  "total_bytes": 75161927680,
  "total_gb": 70.0,
  "threshold_gb": 50.0,
  "detection_window": "last_1_hour",
  "timestamp": "2024-01-15T14:30:00Z",
  "athena_query_id": "abc12345-def6-7890-ghij-klmnopqrstuv"
}
```

---

## 🔐 Security Controls

| Control | Implementation |
|---|---|
| **Encryption at rest** | KMS CMK on S3 bucket and Athena results |
| **Encryption in transit** | `aws:SecureTransport` S3 bucket policy condition |
| **Least privilege IAM** | Scoped delivery roles per spoke account |
| **Log immutability** | S3 Object Lock in COMPLIANCE mode |
| **Access logging** | S3 server access logs on central bucket |
| **Bucket versioning** | Enabled on central log bucket |
| **Block public access** | All four settings enabled on central bucket |
| **Athena workgroup** | Enforces result encryption and query result location |

---

## 💰 Cost Estimation

> Costs vary by log volume. Estimates below assume **100 GB/month** of flow log data across 10 VPCs.

| Service | Estimated Monthly Cost |
|---|---|
| S3 Storage (100 GB) | ~$2.30 |
| S3 PUT requests | ~$0.50 |
| Athena (10 TB scanned — with partitioning ~50 GB effective) | ~$0.25 |
| Glue Crawler (1 DPU-hour/day) | ~$4.40 |
| Lambda (hourly, 128 MB, 30s avg) | ~$0.18 |
| SNS | ~$0.01 |
| **Total** | **~$7.64/month** |

> **Tip:** Enable [Athena Partition Projection](https://docs.aws.amazon.com/athena/latest/ug/partition-projection.html) to eliminate Glue Crawler costs entirely.

---

## 🗺️ Roadmap

- [ ] Athena Partition Projection migration (eliminate Glue Crawler)
- [ ] QuickSight dashboard for traffic visualization
- [ ] AWS Organizations integration for auto-onboarding new accounts
- [ ] ML-based anomaly detection via Amazon SageMaker
- [ ] SIEM integration (Splunk, Datadog, OpenSearch)
- [ ] Slack / PagerDuty alerting channels

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome!

---

## 📄 License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## 👤 Author

Built by an [AWS Ambassador](https://aws.amazon.com/partners/ambassadors/) as a reference implementation for cloud security practitioners.

> ⭐ If you find this useful, please star the repo — it helps other practitioners discover it!
