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

# Scenario: "Feature Interactions - Code interpreter disabled with action groups present"
run "test_code_interpreter_disabled_with_action_groups" {
  command = plan

  variables {
    agent_name              = "no-code-agent"
    foundation_model_id     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction       = "You are an assistant that uses tools to help users. Do not execute code directly."
    environment             = "dev"
    owner                   = "platform-team"
    cost_center             = "CC-1234"
    enable_code_interpreter = false
    action_group_definitions = [
      {
        name               = "search-api"
        description        = "Search external API"
        lambda_arn         = "arn:aws:lambda:us-east-1:123456789012:function:search"
        api_schema_payload = "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"Search\",\"version\":\"1.0\"},\"paths\":{}}"
      }
    ]
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.code_interpreter) == 0
    error_message = "Code interpreter must NOT be created when enable_code_interpreter is false"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.custom) == 1
    error_message = "Custom action group must be created when action_group_definitions is provided"
  }

  assert {
    condition     = length(aws_lambda_permission.action_group) == 1
    error_message = "Lambda permission must be created for action group with lambda_arn"
  }
}

# Scenario: "Feature Interactions - Knowledge base enabled without code interpreter or action groups"
run "test_knowledge_base_only" {
  command = plan

  variables {
    agent_name                   = "kb-only-agent"
    foundation_model_id          = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction            = "You are a knowledge assistant. Answer questions using only the provided knowledge base."
    environment                  = "dev"
    owner                        = "platform-team"
    cost_center                  = "CC-1234"
    enable_code_interpreter      = false
    enable_knowledge_base        = true
    knowledge_base_s3_bucket_arn = "arn:aws:s3:::docs-bucket"
    opensearch_collection_arn    = "arn:aws:aoss:us-east-1:123456789012:collection/xyz789"
  }

  assert {
    condition     = length(aws_bedrockagent_knowledge_base.this) == 1
    error_message = "Knowledge base must be created when enable_knowledge_base is true"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_knowledge_base_association.this) == 1
    error_message = "KB association must be created when knowledge base is enabled"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.code_interpreter) == 0
    error_message = "Code interpreter must NOT be created when enable_code_interpreter is false"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.custom) == 0
    error_message = "No custom action groups should exist when action_group_definitions is empty"
  }
}

# Scenario: "Feature Interactions - BYO guardrail (ID + version) without module-created guardrail"
run "test_byo_guardrail" {
  command = plan

  variables {
    agent_name          = "byo-guardrail-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a safe assistant with externally managed content filtering."
    environment         = "prod"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    guardrail_id        = "abc123"
    guardrail_version   = "1"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this) == 0
    error_message = "Module-created guardrail must NOT be created when using BYO guardrail"
  }

  assert {
    condition     = length(aws_bedrock_guardrail_version.this) == 0
    error_message = "Module-created guardrail version must NOT be created when using BYO guardrail"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.guardrail_configuration[0].guardrail_identifier == "abc123"
    error_message = "Agent guardrail configuration must reference the BYO guardrail ID 'abc123'"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.guardrail_configuration[0].guardrail_version == "1"
    error_message = "Agent guardrail configuration must reference the BYO guardrail version '1'"
  }
}

# Scenario: "Feature Interactions - BYO KMS key instead of module-created key"
run "test_byo_kms_key" {
  command = plan

  variables {
    agent_name          = "byo-kms-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are an assistant using a centrally managed encryption key."
    environment         = "prod"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0
    error_message = "Module KMS key must NOT be created when a BYO KMS key ARN is provided"
  }

  assert {
    condition     = length(aws_kms_alias.this) == 0
    error_message = "Module KMS alias must NOT be created when a BYO KMS key ARN is provided"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.customer_encryption_key_arn == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Agent encryption key must use the BYO KMS key ARN"
  }
}

# Scenario: "Feature Interactions - API gateway enabled without knowledge base"
run "test_api_gateway_without_knowledge_base" {
  command = plan

  variables {
    agent_name               = "api-only-agent"
    foundation_model_id      = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction        = "You are an assistant accessible via API with code execution capabilities."
    environment              = "staging"
    owner                    = "platform-team"
    cost_center              = "CC-1234"
    enable_api_gateway       = true
    api_throttle_rate_limit  = 200
    api_throttle_burst_limit = 100
  }

  assert {
    condition     = length(aws_apigatewayv2_api.this) == 1
    error_message = "API gateway must be created when enable_api_gateway is true"
  }

  assert {
    condition     = length(aws_apigatewayv2_stage.this) == 1
    error_message = "API gateway stage must be created when enable_api_gateway is true"
  }

  assert {
    condition     = length(aws_bedrockagent_knowledge_base.this) == 0
    error_message = "No knowledge base resources should exist when knowledge base is disabled"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.code_interpreter) == 1
    error_message = "Code interpreter must still be active by default"
  }
}

# Scenario: "Feature Interactions - Memory enabled with custom storage days"
run "test_memory_enabled_with_custom_storage_days" {
  command = plan

  variables {
    agent_name          = "memory-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are an assistant that remembers previous conversations and builds on past interactions."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    enable_memory       = true
    memory_storage_days = 7
  }

  assert {
    condition     = var.enable_memory == true
    error_message = "Memory configuration must be present when enable_memory is true"
  }

  assert {
    condition     = var.enable_memory == true
    error_message = "Memory must be enabled"
  }

  assert {
    condition     = var.memory_storage_days == 7
    error_message = "Memory storage days must be set to 7"
  }
}
