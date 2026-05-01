# ---------------------------------------------------------------------------
# Provider Configuration
# ---------------------------------------------------------------------------
# This project uses two providers:
#   - "central" → the Security/Logging account where logs and detection live
#   - "spoke"   → used for module iteration over spoke accounts
#
# For multi-account deployments, configure AWS_PROFILE or pass assume_role ARNs.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "central"
  region = var.central_region

  default_tags {
    tags = local.common_tags
  }
}

# Spoke accounts are handled inside the spoke_account module using assume_role.
# No top-level spoke provider is needed.
