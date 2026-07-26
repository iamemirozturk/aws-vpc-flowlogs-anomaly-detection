# Cost model

Static monthly totals are misleading because vended-log volume, Region,
retention, query behavior, and free tiers vary.

| Input | How to obtain |
|---|---|
| Flow Log GB delivered | Existing telemetry or sandbox sample |
| Compressed GB-month by storage class | S3 metrics/forecast |
| Objects and S3 requests | Inventory or delivery-interval estimate |
| Athena TB scanned per query and runs | Query statistics and schedule |
| KMS, Lambda, SNS/SQS/DynamoDB usage | Service metrics |

```text
monthly cost =
  vended Flow Log delivery
  + S3 storage/requests/access logs
  + Athena bytes scanned
  + KMS requests
  + Lambda, SNS, SQS, DynamoDB, and CloudWatch usage
```

Use current [CloudWatch/VPC Flow Logs pricing](https://aws.amazon.com/cloudwatch/pricing/),
[S3](https://aws.amazon.com/s3/pricing/),
[Athena](https://aws.amazon.com/athena/pricing/),
[KMS](https://aws.amazon.com/kms/pricing/), and
[Lambda](https://aws.amazon.com/lambda/pricing/).

Parquet, exact hourly pruning, the Athena cutoff, S3 bucket keys, 30-day result
expiration, archive transitions, and partition projection constrain cost. The
lifecycle configuration explicitly retains the storage-class-specific minimum
object-size behavior so small Flow Log objects can transition to Glacier classes;
model per-object transition requests and archive metadata because small files can
cost more than they save. Glacier minimum-duration/retrieval charges, Object
Lock, and access-log objects must also be modeled. Build low/expected/high
scenarios and budgets before organization-wide onboarding.
