# Architecture

## Trust and state boundaries

The design has two deployment roots because Terraform provider instances cannot
be selected dynamically for `for_each`. Central security infrastructure and
workload telemetry also have different credentials, owners, and lifecycles.

- The repository root is deployed in the Security/Logging account and owns
  storage, catalog, query, detection, and alerting resources.
- `deployments/spoke` is deployed once per account and Region. It assumes one
  explicit role and creates Flow Logs for a set of VPCs.
- Every root uses independent remote state. Backend bootstrap remains external.
- `allowed_account_ids` and preconditions fail when credentials resolve to the
  wrong account.

## Data path

1. The EC2 Flow Logs service writes enriched Parquet objects directly to central
   S3. An IAM delivery role is for CloudWatch Logs destinations, not this S3
   destination.
2. Hive-compatible hourly prefixes encode account, service, Region, year,
   month, day, and hour.
3. An explicit Glue table describes the schema. Athena partition projection
   maps predicates to prefixes without a crawler.
4. EventBridge invokes Lambda at the same interval as the detection window.
   Lambda derives a delayed half-open record-end window from the event timestamp
   and submits a partition-pruned Athena query.
5. Lambda publishes one bounded SNS notification when sources exceed the
   threshold, then records the completed window in DynamoDB.

```text
s3://BUCKET/AWSLogs/
  aws-account-id=ACCOUNT/aws-service=vpcflowlogs/aws-region=REGION/
  year=YYYY/month=MM/day=DD/hour=HH/
```

## Detector model

The custom record includes default fields plus VPC, subnet, instance, TCP flag,
packet address, AWS service, direction, and traffic path context. Packet
addresses are preferred because intermediate network interfaces can change
`srcaddr` and `dstaddr`.

The half-open record-assignment interval is:

```text
[EventBridge time - delay - window, EventBridge time - delay)
```

The query assigns a Flow Log record to the window containing its `end` timestamp,
keeps accepted egress with `log_status = OK`, removes non-public destinations,
aggregates bytes by destination, then aggregates every destination for each
account/instance/source. This avoids counting one record in adjacent windows and
closes the original bug where traffic split across many destinations could
remain under each per-destination threshold. Counters still describe the full
Flow Log aggregation record, so a record can include traffic that began shortly
before the window.

## Authorization and storage

The central bucket grants `delivery.logs.amazonaws.com` `PutObject` only to
each enrolled Hive account prefix. Each write statement pairs the source account
with its logs-service source ARN. `GetBucketAcl` uses the same confused-deputy
conditions.

The Flow Logs KMS key restricts the delivery service to the central bucket
encryption context. Lambda permissions scope Athena to one workgroup, Glue to
one catalog/database/table, S3 to log and result prefixes, and KMS to the
project keys. A separate detector policy covers its topic and state table.

All buckets block public access, enforce ownership, version objects, and deny
non-TLS requests. Flow Logs and query results use customer-managed keys and S3
bucket keys. Server access logs use a separate encrypted, versioned bucket.
Athena results expire after 30 days. Flow Logs transition to archive tiers;
current-object expiration is optional.

Object Lock is opt-in and defaults to GOVERNANCE mode. Server access logging is
not an independent immutable audit trail; high-assurance deployments should
evaluate organization CloudTrail data events under a separately managed trail.

## Failure behavior

- Athena failures and timeouts become Lambda errors; queries are stopped before
  Lambda runs out of time.
- SNS failures are not swallowed, and a completion record is not written.
- Reserved concurrency prevents overlapping detector runs.
- Lambda retries handler failures twice. EventBridge separately retries target
  delivery failures. Events that exhaust either path go to the encrypted SQS
  DLQ.
- CloudWatch alarms cover Lambda errors, throttles, and DLQ messages.

There is a narrow at-least-once boundary after SNS accepts a message and before
DynamoDB records completion. Consumers should deduplicate using environment and
window timestamps.

## Scale and availability

The system is regional and has no cross-Region failover. The S3 bucket policy
has a 20 KB limit; one write statement per account/Region provides strong
pairing but may not scale to a very large organization. At that point, evaluate
an Organizations condition and automated onboarding with explicit tests.

The Athena scan cutoff can reject legitimate high-volume windows. Tune it from
query statistics rather than removing it.
