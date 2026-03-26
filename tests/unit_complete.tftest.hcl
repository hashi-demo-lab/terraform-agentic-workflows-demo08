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

# Scenario: "Full Features (complete)"
run "test_all_features_enabled" {
  command = plan

  variables {
    agent_name                     = "full-featured-agent"
    foundation_model_id            = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction              = "You are a comprehensive assistant with access to knowledge bases, tools, and code execution capabilities. Use all available resources to help users."
    environment                    = "prod"
    owner                          = "ml-engineering"
    cost_center                    = "CC-5678"
    idle_session_ttl               = 1800
    enable_code_interpreter        = true
    enable_memory                  = true
    memory_storage_days            = 14
    enable_knowledge_base          = true
    knowledge_base_s3_bucket_arn   = "arn:aws:s3:::my-kb-documents"
    knowledge_base_embedding_model = "amazon.titan-embed-text-v2:0"
    knowledge_base_description     = "Product documentation and FAQs"
    opensearch_collection_arn      = "arn:aws:aoss:us-east-1:123456789012:collection/abc123def456"
    opensearch_vector_index_name   = "product-docs-index"
    action_group_definitions = [
      {
        name               = "lookup-order"
        description        = "Look up customer order status"
        lambda_arn         = "arn:aws:lambda:us-east-1:123456789012:function:order-lookup"
        api_schema_payload = "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"Order API\",\"version\":\"1.0\"},\"paths\":{}}"
      }
    ]
    enable_api_gateway       = true
    api_throttle_rate_limit  = 500
    api_throttle_burst_limit = 200
    guardrail_config = {
      name = "full-guardrail"
      content_filters = [
        { type = "HATE", input_strength = "HIGH", output_strength = "HIGH" },
        { type = "VIOLENCE", input_strength = "HIGH", output_strength = "HIGH" },
        { type = "PROMPT_ATTACK", input_strength = "HIGH", output_strength = "HIGH" }
      ]
      pii_filters = [
        { type = "EMAIL", action = "ANONYMIZE" },
        { type = "PHONE", action = "BLOCK" }
      ]
    }
    log_retention_days = 365
    tags               = { Team = "ml-engineering" }
  }

  assert {
    condition     = aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 1800
    error_message = "Agent idle session TTL must be set to 1800 seconds"
  }

  assert {
    condition     = var.enable_memory == true
    error_message = "Memory must be enabled"
  }

  assert {
    condition     = var.memory_storage_days == 14
    error_message = "Memory storage days must be set to 14"
  }

  assert {
    condition     = length(aws_bedrockagent_knowledge_base.this) == 1
    error_message = "Knowledge base must be created when enabled"
  }

  assert {
    condition     = length(aws_iam_role.knowledge_base) == 1
    error_message = "Knowledge base IAM role must be created when knowledge base is enabled"
  }

  assert {
    condition     = length(aws_bedrockagent_data_source.this) == 1
    error_message = "Data source must be created when knowledge base is enabled"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_knowledge_base_association.this) == 1
    error_message = "Knowledge base association must be created when knowledge base is enabled"
  }

  assert {
    condition     = aws_bedrockagent_agent_knowledge_base_association.this[0].description == "Product documentation and FAQs"
    error_message = "KB association description must be set to the knowledge_base_description value"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.custom) == 1
    error_message = "Custom action group must be created when action_group_definitions is provided"
  }

  assert {
    condition     = length(aws_lambda_permission.action_group) == 1
    error_message = "Lambda permission must be created for action group with lambda_arn"
  }

  assert {
    condition     = length(aws_bedrockagent_agent_action_group.code_interpreter) == 1
    error_message = "Code interpreter must still be created alongside custom action groups"
  }

  assert {
    condition     = length(aws_apigatewayv2_api.this) == 1
    error_message = "API gateway must be created when enable_api_gateway is true"
  }

  assert {
    condition     = aws_apigatewayv2_api.this[0].protocol_type == "HTTP"
    error_message = "API gateway must use HTTP protocol"
  }

  assert {
    condition     = length(aws_apigatewayv2_stage.this) == 1
    error_message = "API gateway stage must be created when enable_api_gateway is true"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this) == 1
    error_message = "Guardrail must be created when guardrail_config is provided"
  }

  assert {
    condition     = length(aws_bedrock_guardrail_version.this) == 1
    error_message = "Guardrail version must be created when guardrail_config is provided"
  }

  assert {
    condition     = aws_bedrock_guardrail.this[0].blocked_input_messaging == "Sorry, I cannot process that request."
    error_message = "Guardrail blocked input messaging must use the default value"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "Log retention must be set to 365 days"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Team"] == "ml-engineering"
    error_message = "Custom tag 'Team' must be propagated to the agent"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Environment"] == "prod"
    error_message = "Environment tag must be 'prod'"
  }

  assert {
    condition     = aws_bedrockagent_agent_alias.this.agent_alias_name != null
    error_message = "Agent alias must exist to trigger agent preparation"
  }
}
