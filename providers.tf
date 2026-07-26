provider "aws" {
  region              = var.central_region
  allowed_account_ids = [var.central_account_id]

  default_tags {
    tags = local.common_tags
  }
}
