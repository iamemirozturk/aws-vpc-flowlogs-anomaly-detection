# GitHub repository settings checklist

These settings cannot be represented reliably in the repository tree. Apply
them through a reviewed administrator change after the corrected branch is
published.

## About

- Description: `Centralized multi-account VPC Flow Logs detection with
  Terraform, S3, Athena, Lambda, and SNS`
- Topics: `aws-security`, `vpc-flow-logs`, `terraform`, `athena`,
  `threat-detection`, `cloud-security`, `multi-account`
- Social preview: export `docs/architecture.svg` at a suitable social-card size
- Website: use a real demo/article URL or leave it empty

## Default branch and protection

1. Rename the current `aws` default branch to `main` after checking open clones,
   links, and automation.
2. Keep both branch names in the workflow during migration; remove `aws` only
   after the rename is complete.
3. Protect `main` with:
   - pull requests and at least one approval;
   - stale approval dismissal;
   - code-owner review for sensitive paths;
   - conversation resolution;
   - required `Terraform and Python quality`, `tfsec`, and `Checkov` checks;
   - blocked force pushes and deletion;
   - administrator enforcement appropriate to the project.

## Security features

- Keep secret scanning and push protection enabled.
- Enable Dependabot alerts and security updates.
- Enable private vulnerability reporting.
- Enable code scanning so workflow SARIF uploads appear in Security.
- Review GitHub Actions policy and allow only required, SHA-pinned actions.
- Set the workflow token default to read-only.

## Portfolio evidence

After a sandbox integration demo:

1. Add redacted evidence using `docs/demo.md`.
2. Create a signed `v1.0.0` release from a green protected commit.
3. Include architecture, threat model, test evidence, deployment limitations,
   migration notes, and the exact validated Terraform/provider versions in the
   release notes.

Do not claim an AWS program title, compliance certification, production use, or
measured savings without public, verifiable evidence.
