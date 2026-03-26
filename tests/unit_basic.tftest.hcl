# Generated from specs/001-bedrock-agentcore/design.md Section 5

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
      user_id    = "AKIAIOSFODNN7EXAMPLE"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# Scenario: "Secure Defaults (basic)"
run "test_agent_created_with_correct_name" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise and accurate in your responses."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.agent_name == "test-agent"
    error_message = "Agent must be created with the name 'test-agent'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.foundation_model == "anthropic.claude-3-5-sonnet-20241022-v2:0"
    error_message = "Agent must use the specified foundation model 'anthropic.claude-3-5-sonnet-20241022-v2:0'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.instruction == "You are a helpful assistant that answers questions about cloud infrastructure. Be concise and accurate in your responses."
    error_message = "Agent instruction must match the provided instruction prompt"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.prepare_agent == false
    error_message = "Agent prepare_agent must be false because the alias handles preparation"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.skip_resource_in_use_check == true
    error_message = "Agent skip_resource_in_use_check must be true"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 600
    error_message = "Agent idle session TTL must default to 600 seconds"
  }

  assert {
    condition     = length(aws_kms_key.this) == 1
    error_message = "KMS key must be created when no BYO key is provided"
  }

  assert {
    condition     = aws_kms_key.this[0].enable_key_rotation == true
    error_message = "KMS key rotation must be enabled"
  }

  # Agent encryption key is [plan-unknown] -- substitute resource existence check
  assert {
    condition     = length(aws_kms_key.this[*]) == 1
    error_message = "Agent encryption key must be set (KMS key resource must exist)"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.code_interpreter) == 1
    error_message = "Code interpreter action group must be created by default"
  }

  assert {
    condition     = aws_bedrockagent_agent_action_group.code_interpreter[0].parent_action_group_signature == "AMAZON.CodeInterpreter"
    error_message = "Code interpreter must use the AMAZON.CodeInterpreter signature"
  }

  assert {
    condition     = aws_bedrockagent_agent_alias.this.agent_alias_name != null
    error_message = "Agent alias must be created"
  }

  assert {
    condition     = aws_bedrockagent_agent_alias.this.agent_alias_name == "live"
    error_message = "Agent alias name must be 'live'"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/bedrock/agent/test-agent"
    error_message = "CloudWatch log group must be created with correct name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90
    error_message = "Log retention must default to 90 days"
  }

  assert {
    condition     = aws_iam_role.agent.name != null
    error_message = "Agent IAM role must be created"
  }

  assert {
    condition     = length(aws_bedrockagent_knowledge_base.this) == 0
    error_message = "No knowledge base resources should exist when knowledge base is disabled"
  }

  assert {
    condition     = length(aws_apigatewayv2_api.this) == 0
    error_message = "No API gateway should exist when API gateway is disabled"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this) == 0
    error_message = "No guardrail should exist when guardrail is not configured"
  }

  assert {
    condition     = var.enable_memory == false
    error_message = "Memory must be disabled by default"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Environment"] == "dev"
    error_message = "Agent tags must include Environment = 'dev'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["ManagedBy"] == "terraform"
    error_message = "Agent tags must include ManagedBy = 'terraform'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Owner"] == "platform-team"
    error_message = "Agent tags must include Owner = 'platform-team'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["CostCenter"] == "CC-1234"
    error_message = "Agent tags must include CostCenter = 'CC-1234'"
  }
}
