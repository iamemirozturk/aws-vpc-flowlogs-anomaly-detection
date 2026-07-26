# Threat model

## Scope

Protected assets are Flow Log records, Athena results, detector code and
configuration, alerts, idempotency state, Terraform state, and detector
availability. The model excludes compromise of the Organizations management
account, backend bootstrap, recipient mailbox security, and automated response.

## Trust boundaries

| Boundary | Primary control |
|---|---|
| Spoke service to central S3 | Service principal, exact source account/ARN, account prefix |
| S3/catalog to Lambda | Read-only log prefix, scoped Glue/workgroup/KMS permissions |
| Lambda/SNS to recipient | Encrypted topic, bounded message, confirmed subscription |
| Operator to AWS | Short-lived credentials, assume role, account allowlist |
| Deployment to state | External encrypted/locked backend and separate keys |

## Threats and residual risk

| Threat | Treatment | Residual risk |
|---|---|---|
| Confused-deputy bucket write | Source account/ARN and exact prefix | Policy-size limit at organization scale |
| Spoke deletes evidence | Separate account; no spoke delete grant | Central admins remain privileged |
| Public/plaintext data | Public-access blocks, TLS deny, encryption | Drift outside Terraform |
| Full-history query | Projected hour and exact epoch filters, scan cutoff | Missing source enumeration omits data |
| Late records | Configurable delay | Delivery can exceed the delay |
| NAT/appliance attribution | Packet addresses and instance/interface context | Some topology remains ambiguous |
| Split-destination evasion | Threshold after source-level total | Low-and-slow traffic remains |
| Duplicate alerts | Stable event window, DynamoDB, one concurrency | Crash after SNS and before state write |
| Silent failure | Unsuppressed exceptions, alarms, DLQ | Alert topic can also fail |
| Sensitive alert content | Bounded encrypted payload | Email can export telemetry |
| Supply-chain compromise | Lock files, constraints, CI, Dependabot | Releases/actions still require review |

## Assumptions

- Every intended VPC has a project-managed Flow Log with the documented format.
- `log_sources` includes every legitimate account/Region.
- Operators tune threshold, delay, window, exclusions, and scan cutoff from
  representative traffic.
- Alert recipients treat a volume threshold as a lead, not proof.

## Not automatically detected

- Low-and-slow exfiltration below the threshold.
- Transfers to allowed or mistakenly excluded CIDRs.
- Service-mediated transfer where the network address hides the recipient.
- Traffic from unenrolled VPCs or `SKIPDATA` records.
- Disabling Flow Logs by a privileged spoke operator.
- Compromise of the central account, state backend, or alert recipient.

Use AWS Config/Security Hub for Flow Log drift, CloudTrail for control-plane
events, and an independent detector-health path when assurance requires it.
