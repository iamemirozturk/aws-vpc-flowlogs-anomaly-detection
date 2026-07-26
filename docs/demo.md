# Demo and evidence guide

Produce evidence tied to a commit without exposing account IDs, VPC IDs, email
addresses, object keys, or customer traffic.

## Static evidence

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=deployments/spoke init -backend=false
terraform -chdir=deployments/spoke validate
terraform -chdir=deployments/spoke test
tflint --recursive
.venv/bin/python -m pytest
.venv/bin/python -m flake8 lambda
```

Capture the command, tool version, commit SHA, date, and unedited result.

## Sandbox demo

1. Deploy central resources and one disposable spoke VPC.
2. Confirm SNS and wait for a full delivery interval.
3. Verify a Parquet object under the expected Hive prefix.
4. Run `top_talkers.sql` and record Athena bytes scanned.
5. Temporarily lower the sandbox threshold to a reviewed test value.
6. Invoke Lambda with a fixed EventBridge timestamp containing the records.
7. Capture the redacted structured alert.
8. Replay the same payload and capture `duplicateSkipped: true`.
9. Restore the intended threshold.

Only send traffic to an endpoint you own and are authorized to test.

For failure evidence, make a disposable target fail, confirm EventBridge retries,
the DLQ message, and the DLQ alarm, then recover with the original event.

Useful screenshots show a plan summary, redacted Hive prefix, Glue projection
properties, Athena statistics/result, Lambda query window, sanitized alert,
idempotent replay, and green CI. Review the entire image for sensitive browser,
terminal, ARN, email, query, or key data. The repository intentionally includes
no fabricated console screenshots.
