# Generated from specs/001-bedrock-agentcore/design.md Section 5

# Acceptance tests use real providers with command = plan.
# Validates plan output against real AWS APIs without creating resources.
# Requires AWS credentials. Not run during unit test workflow.

# Scenario: "Acceptance - Plan Verification"
run "test_plan_verification" {
  command = plan

  variables {
    agent_name          = "acceptance-test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant for acceptance testing. Answer questions accurately and concisely."
    environment         = "dev"
    owner               = "test-team"
    cost_center         = "CC-TEST"
  }

  assert {
    condition     = can(regex("^arn:aws:bedrock:", aws_bedrockagent_agent.this.agent_arn))
    error_message = "Agent ARN must follow the expected format (arn:aws:bedrock:...)"
  }

  assert {
    condition     = can(regex("^arn:aws:kms:", aws_kms_key.this[0].arn))
    error_message = "KMS key ARN must follow the expected format (arn:aws:kms:...)"
  }

  assert {
    condition     = can(regex("^arn:aws:iam:", aws_iam_role.agent.arn))
    error_message = "Agent role ARN must follow the expected format (arn:aws:iam:...)"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/bedrock/agent/acceptance-test-agent"
    error_message = "Log group name must be '/aws/bedrock/agent/acceptance-test-agent'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.customer_encryption_key_arn != null
    error_message = "Agent encryption key ARN must be populated"
  }
}
