# Contributing

1. Fork and create a focused branch.
2. Never commit credentials, state, account identifiers, topology, Flow Log
   records, query results, or email addresses.
3. Keep central and spoke state boundaries intact.
4. Update tests and documentation with behavior changes.
5. Run:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=deployments/spoke init -backend=false
terraform -chdir=deployments/spoke validate
terraform -chdir=deployments/spoke test
tflint --init && tflint --recursive
.venv/bin/python -m pytest
.venv/bin/python -m flake8 lambda
```

Constrain providers, commit lock files, validate sensitive inputs, scope IAM,
and explain scanner suppressions. Flag state moves, replacements, retention,
and cost changes. Do not use `-target` as a deployment workflow.

Keep AWS clients mockable, test time/failure boundaries, do not swallow
notification failures, and bound query/alert output. Athena queries require
partition and epoch filters; quote `"start"` and `"end"`.

Distinguish implementation from prerequisites and roadmap. Do not claim
compliance or savings without evidence. Update the SVG and architecture text
together.

Report vulnerabilities through [SECURITY.md](SECURITY.md). See
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
