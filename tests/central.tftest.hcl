mock_provider "aws" {
  override_during = plan

  override_data {
    target = module.central_logging.data.aws_caller_identity.current
    values = {
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

mock_provider "archive" {
  override_during = plan
}

run "central_configuration_plans" {
  command = plan

  variables {
    central_account_id = "111122223333"
    central_region     = "us-east-1"
    log_bucket_name    = "example-security-flowlogs"
    log_sources = [
      {
        account_id = "444455556666"
        regions    = ["us-east-1", "eu-west-1"]
      },
    ]
  }

  assert {
    condition     = output.central_log_bucket_name == "example-security-flowlogs"
    error_message = "The configured central bucket name was not preserved."
  }

  assert {
    condition     = output.glue_table_name == "flow_logs"
    error_message = "The detector and explicit Glue table must use flow_logs."
  }

  assert {
    condition = (
      module.central_logging.lifecycle_transition_minimum_object_size ==
      "varies_by_storage_class"
    )
    error_message = "Flow Log lifecycle transitions must explicitly include small archive objects."
  }

  assert {
    condition     = module.detection_engine.maximum_retry_attempts == 2
    error_message = "Transient detector failures must receive two Lambda asynchronous retries."
  }

  assert {
    condition     = module.detection_engine.schedule_expression == "rate(60 minutes)"
    error_message = "The invocation interval must equal the detection window."
  }
}
