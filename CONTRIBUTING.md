# Contributing to aws-vpc-flowlogs-anomaly-detection

Thank you for your interest in contributing! This project is maintained as a reference implementation for AWS security practitioners. All contributions are welcome.

---

## Getting Started

1. **Fork** the repository and clone your fork locally.
2. Create a **feature branch**: `git checkout -b feat/your-feature-name`
3. Make your changes following the guidelines below.
4. **Test** your Terraform changes: `terraform init -backend=false && terraform validate && terraform fmt -check -recursive`
5. Open a **Pull Request** against `main` with a clear description.

---

## Development Setup

```bash
# Install tools
brew install terraform tfsec checkov

# Install pre-commit hooks
pip install pre-commit
pre-commit install

# Validate all modules
terraform init -backend=false
terraform validate
terraform fmt -recursive
tfsec .
checkov -d . --framework terraform
```

---

## Contribution Guidelines

### Terraform
- All resources must have `tags` applied via the `local.common_tags` pattern.
- No hard-coded account IDs, bucket names, or ARNs — use variables.
- All variables must include `description` and `validation` blocks where applicable.
- Run `terraform fmt -recursive` before committing.

### Lambda (Python)
- Target Python 3.12.
- Follow PEP 8. Use type hints.
- All functions must have docstrings.
- Unit test new logic in `lambda/tests/`.

### SQL Queries
- Use `{{placeholder}}` syntax for parameterized values.
- Always include partition filters (`year`, `month`, `day`) to prevent full scans.
- Add a comment block at the top of each file explaining purpose and usage.

### Documentation
- Update `README.md` if you add a new module, feature, or query.
- Add architectural changes to `docs/architecture.md` and update `docs/architecture.drawio`.

---

## Reporting Issues

Please use [GitHub Issues](../../issues) and include:
- Terraform version (`terraform version`)
- AWS provider version
- Error message and stack trace
- Minimal reproduction steps

---

## Code of Conduct

Be kind, constructive, and professional. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
