# Generated from specs/001-bedrock-agentcore/design.md Section 5

# Integration tests use real providers with command = apply.
# Creates and destroys real infrastructure in AWS.
# Requires AWS credentials. Not run during unit test workflow.

# Scenario: "Integration - End-to-End"
run "test_end_to_end" {
  command = apply

  variables {
    agent_name              = "integration-test-agent"
    foundation_model_id     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction       = "You are an integration test agent. Answer all questions with 'Integration test successful.' for verification purposes."
    environment             = "dev"
    owner                   = "test-team"
    cost_center             = "CC-TEST"
    enable_code_interpreter = true
  }

  assert {
    condition     = output.agent_id != ""
    error_message = "Agent ID must be populated after apply"
  }

  assert {
    condition     = output.agent_arn != ""
    error_message = "Agent ARN must be populated after apply"
  }

  assert {
    condition     = output.agent_alias_id != ""
    error_message = "Agent alias ID must be populated after apply"
  }

  assert {
    condition     = output.agent_alias_arn != ""
    error_message = "Agent alias ARN must be populated after apply"
  }

  assert {
    condition     = output.agent_role_arn != ""
    error_message = "Agent role ARN must be populated after apply"
  }

  assert {
    condition     = output.kms_key_arn != ""
    error_message = "KMS key ARN must be populated after apply"
  }

  assert {
    condition     = output.log_group_name == "/aws/bedrock/agent/integration-test-agent"
    error_message = "Log group name must match expected pattern '/aws/bedrock/agent/integration-test-agent'"
  }

  assert {
    condition     = output.knowledge_base_id == null
    error_message = "Knowledge base ID must be null when knowledge base is disabled"
  }

  assert {
    condition     = output.api_endpoint == null
    error_message = "API endpoint must be null when API gateway is disabled"
  }
}
