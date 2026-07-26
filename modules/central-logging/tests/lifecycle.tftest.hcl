mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "valid_archive_spacing_plans" {
  command = plan

  variables {
    central_account_id           = "111122223333"
    log_bucket_name              = "example-security-flowlogs"
    glacier_transition_days      = 90
    deep_archive_transition_days = 180
    log_sources = [
      {
        account_id = "444455556666"
        regions    = ["us-east-1"]
      },
    ]
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.central_logs.transition_default_minimum_object_size ==
      "varies_by_storage_class"
    )
    error_message = "Flow Log lifecycle transitions must explicitly include small archive objects."
  }
}

run "invalid_archive_spacing_is_rejected" {
  command = plan

  variables {
    central_account_id           = "111122223333"
    log_bucket_name              = "example-security-flowlogs"
    glacier_transition_days      = 90
    deep_archive_transition_days = 179
    log_sources = [
      {
        account_id = "444455556666"
        regions    = ["us-east-1"]
      },
    ]
  }

  expect_failures = [
    aws_s3_bucket.central_logs,
  ]
}
