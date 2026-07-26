# Security policy

## Supported versions

Security fixes are applied to the current default branch. This repository is a
reference implementation, not a managed service; operators remain responsible
for reviewing plans, protecting state, monitoring resources, and applying
updates.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this
repository. Do not open a public issue for a suspected vulnerability and do not
include AWS credentials, account identifiers, VPC Flow Log records, Terraform
state, or other customer data.

Include a concise impact statement, affected files or resources, reproduction
steps using sanitized data, and any suggested remediation. The maintainer will
acknowledge a complete report as soon as practical and coordinate disclosure
after a fix is available.

## Deployment security

- Review every Terraform plan and deploy with short-lived credentials.
- Store central and spoke state separately in encrypted, versioned backends with
  state locking and tightly scoped access.
- Confirm SNS email subscriptions and test the EventBridge dead-letter queue.
- Start with Object Lock disabled; enabling it is an irreversible bucket
  property. Validate retention and break-glass procedures before using
  COMPLIANCE mode.
- Treat destination IPs and network metadata in alerts as sensitive telemetry.
