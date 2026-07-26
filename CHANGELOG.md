# Changelog

All notable changes are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Separate spoke deployment root and state boundary.
- Explicit partition-projected Glue table for enriched Parquet Flow Logs.
- Delayed record-end window detector with IPv4/IPv6 exclusions, aggregated
  alerts, DynamoDB idempotency, a shared failure DLQ, and alarms.
- Unit tests, Flake8, TFLint, dependency updates, and hardened CI.
- Security policy, issue templates, pull-request checklist, and operational
  documentation.

### Changed

- Replaced broad service policies with source-account/source-ARN conditions and
  resource-scoped Lambda permissions.
- Made Object Lock opt-in and documented its irreversible behavior.
- Replaced mutable CI scanner references and removed dummy AWS credentials.
- Coupled the detector schedule to its window, enabled two handler retries, and
  fingerprinted retry state with the detector configuration.
- Assigned Flow Log records to windows by end timestamp and corrected GiB labels.
- Made small-object archive transition behavior explicit and enforced the
  Glacier Flexible Retrieval minimum duration before Deep Archive.
- Kept security scans independent from the quality job and corrected Python
  dependency caching.

### Removed

- Invalid cross-account provider iteration and targeted-apply workflow.
- Unnecessary S3 Flow Logs IAM delivery role.
- Glue crawler and its broad AWS-managed service role.
