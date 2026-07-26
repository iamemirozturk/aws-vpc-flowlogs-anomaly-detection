## What changed

Describe the security or operational problem and the implementation.

## Validation

- [ ] `terraform fmt -check -recursive`
- [ ] Central root initialized and validated
- [ ] Spoke root initialized and validated
- [ ] `tflint --recursive`
- [ ] `python -m pytest`
- [ ] `python -m flake8 lambda`
- [ ] Documentation and cost/security implications updated

## Risk and rollout

Describe state migrations, replacement-prone resources, IAM changes, and rollback.
