# Changelog

All notable changes are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Separate spoke deployment root and state boundary.
- Explicit partition-projected Glue table for enriched Parquet Flow Logs.
- Exact rolling-window detector with delayed ingestion, IPv4/IPv6 exclusions,
  aggregated alerts, DynamoDB idempotency, EventBridge DLQ, and alarms.
- Unit tests, Flake8, TFLint, dependency updates, and hardened CI.
- Security policy, issue templates, pull-request checklist, and operational
  documentation.

### Changed

- Replaced broad service policies with source-account/source-ARN conditions and
  resource-scoped Lambda permissions.
- Made Object Lock opt-in and documented its irreversible behavior.
- Replaced mutable CI scanner references and removed dummy AWS credentials.

### Removed

- Invalid cross-account provider iteration and targeted-apply workflow.
- Unnecessary S3 Flow Logs IAM delivery role.
- Glue crawler and its broad AWS-managed service role.
