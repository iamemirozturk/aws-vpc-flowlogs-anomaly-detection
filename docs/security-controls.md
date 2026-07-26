# Security controls

| Objective | Implementation | Verification |
|---|---|---|
| Correct AWS account | Provider account allowlist and resource preconditions | Plan with a wrong profile must fail |
| Cross-account delivery | Service principal, account prefix, source account/ARN | Inspect Flow Log delivery status |
| Encryption | Customer keys for logs/results/alerts/state/log group; SQS SSE | Inspect APIs and key policies |
| TLS-only S3 | Explicit insecure-transport deny on every bucket | Policy test in a sandbox |
| No public S3 | All Block Public Access settings and owner enforcement | AWS Config/Security Hub |
| Retention/integrity | Versioning, lifecycle, optional Object Lock | Review plan and retention APIs |
| Least privilege | Scoped workgroup, catalog/table, prefixes, keys, topic, table | IAM Access Analyzer and CloudTrail |
| Query cost | Projection, hour/epoch filters, bytes-scanned cutoff | Athena statistics |
| Reliable execution | Concurrency, retries, DLQ, health alarms | Controlled failure demo |
| Retry idempotency | Stable window and DynamoDB completion record | Replay the same event |
| Dependency hygiene | Version constraints, lock files, scanners, Dependabot | CI and dependency review |

## Operator-owned controls

- Protect the Terraform backend with separate encryption, versioning, logging,
  locking, and least privilege.
- Restrict and monitor central and spoke deployment roles.
- Configure GitHub branch protection, required reviews/checks, private
  vulnerability reporting, secret scanning, and Dependabot security updates.
- Monitor changes to Flow Logs, policies, keys, schedules, alarms, and
  subscriptions with CloudTrail and AWS Config.
- Use an independent health path if SNS failure must not suppress health alarms.
- Obtain compliance/legal approval before Object Lock.

These controls can contribute evidence to a compliance program. Deploying the
repository does not certify CIS, NIST, SOC 2, PCI DSS, or another framework.

## Documented scanner exceptions

Checkov/tfsec suppressions are narrow and explained next to the resource:

- KMS key policies require `Resource = "*"` and an account-root `kms:*`
  statement to enable IAM delegation; service statements remain principal- and
  context-constrained.
- AWS requires an S3 server-access-log destination to use SSE-S3, so the access
  bucket cannot meet a generic customer-key rule.
- No cross-Region replication is implemented in this regional reference.
- Buckets without an event-driven consumer do not emit unused notifications.
- Lambda remains outside a VPC because it uses AWS APIs only; VPC attachment
  would add NAT/endpoints, cost, and attack surface.
- AWS Signer is not implemented because the locally generated archive has no
  signing pipeline. The archive hash, CI tests, scanner results, and reviewed
  Terraform plan are compensating controls, not equivalent assurance.

Reassess these decisions for the target organization's threat model rather than
copying the suppressions into a production standard unchanged.
