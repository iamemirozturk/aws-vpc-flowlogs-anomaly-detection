mock_provider "aws" {
  override_during = plan

  override_data {
    target = module.vpc_flow_logs.data.aws_caller_identity.current
    values = {
      account_id = "444455556666"
    }
  }
}

run "spoke_configuration_plans" {
  command = plan

  variables {
    spoke_account_id       = "444455556666"
    region                 = "us-east-1"
    deployment_role_arn    = "arn:aws:iam::444455556666:role/TerraformDeploymentRole"
    vpc_ids                = ["vpc-0aaa1111bbbb2222c"]
    central_log_bucket_arn = "arn:aws:s3:::example-security-flowlogs"
  }

  assert {
    condition     = length(output.flow_log_ids) == 1
    error_message = "The spoke root must create one Flow Log for each VPC ID."
  }
}
