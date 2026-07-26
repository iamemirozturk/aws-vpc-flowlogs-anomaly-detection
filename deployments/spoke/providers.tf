provider "aws" {
  region              = var.region
  allowed_account_ids = [var.spoke_account_id]

  assume_role {
    role_arn     = var.deployment_role_arn
    session_name = "vpc-flowlogs-terraform"
  }

  default_tags {
    tags = local.common_tags
  }
}
