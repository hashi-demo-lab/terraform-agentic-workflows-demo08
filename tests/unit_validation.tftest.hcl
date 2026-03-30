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

# === Validation Errors (reject) ===

# Scenario: "Validation Errors - agent_instruction 39 characters rejected"
run "test_agent_instruction_below_minimum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "This string has exactly 39 characters."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  expect_failures = [var.agent_instruction]
}

# Scenario: "Validation Errors - agent_instruction 20001 characters rejected"
run "test_agent_instruction_above_maximum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = format("%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s", join("", [for i in range(1000) : "a"]), join("", [for i in range(1000) : "b"]), join("", [for i in range(1000) : "c"]), join("", [for i in range(1000) : "d"]), join("", [for i in range(1000) : "e"]), join("", [for i in range(1000) : "f"]), join("", [for i in range(1000) : "g"]), join("", [for i in range(1000) : "h"]), join("", [for i in range(1000) : "i"]), join("", [for i in range(1000) : "j"]), join("", [for i in range(1000) : "k"]), join("", [for i in range(1000) : "l"]), join("", [for i in range(1000) : "m"]), join("", [for i in range(1000) : "n"]), join("", [for i in range(1000) : "o"]), join("", [for i in range(1000) : "p"]), join("", [for i in range(1000) : "q"]), join("", [for i in range(1000) : "r"]), join("", [for i in range(1000) : "s"]), join("", [for i in range(1000) : "t"]), "x")
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  expect_failures = [var.agent_instruction]
}

# Scenario: "Validation Errors - idle_session_ttl 59 rejected"
run "test_idle_session_ttl_below_minimum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    idle_session_ttl    = 59
  }

  expect_failures = [var.idle_session_ttl]
}

# Scenario: "Validation Errors - idle_session_ttl 3601 rejected"
run "test_idle_session_ttl_above_maximum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    idle_session_ttl    = 3601
  }

  expect_failures = [var.idle_session_ttl]
}

# Scenario: "Validation Errors - memory_storage_days -1 rejected"
run "test_memory_storage_days_below_minimum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    memory_storage_days = -1
  }

  expect_failures = [var.memory_storage_days]
}

# Scenario: "Validation Errors - memory_storage_days 31 rejected"
run "test_memory_storage_days_above_maximum_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    memory_storage_days = 31
  }

  expect_failures = [var.memory_storage_days]
}

# Scenario: "Validation Errors - environment 'production' rejected"
run "test_invalid_environment_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "production"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  expect_failures = [var.environment]
}

# Scenario: "Validation Errors - log_retention_days 2 rejected"
run "test_invalid_log_retention_days_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    log_retention_days  = 2
  }

  expect_failures = [var.log_retention_days]
}

# Scenario: "Validation Errors - agent_name with invalid characters rejected"
run "test_agent_name_invalid_characters_rejected" {
  command = plan

  variables {
    agent_name          = "invalid agent!"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  expect_failures = [var.agent_name]
}

# Scenario: "Validation Errors - kms_key_arn invalid ARN rejected"
run "test_invalid_kms_key_arn_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    kms_key_arn         = "not-an-arn"
  }

  expect_failures = [var.kms_key_arn]
}

# Scenario: "Validation Errors - api_throttle_rate_limit 0 rejected"
run "test_api_throttle_rate_limit_below_minimum_rejected" {
  command = plan

  variables {
    agent_name              = "test-agent"
    foundation_model_id     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction       = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment             = "dev"
    owner                   = "platform-team"
    cost_center             = "CC-1234"
    api_throttle_rate_limit = 0
  }

  expect_failures = [var.api_throttle_rate_limit]
}

# Scenario: "Validation Errors - api_throttle_burst_limit 0 rejected"
run "test_api_throttle_burst_limit_below_minimum_rejected" {
  command = plan

  variables {
    agent_name               = "test-agent"
    foundation_model_id      = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction        = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment              = "dev"
    owner                    = "platform-team"
    cost_center              = "CC-1234"
    api_throttle_burst_limit = 0
  }

  expect_failures = [var.api_throttle_burst_limit]
}

# Scenario: "Validation Errors - guardrail_version 'DRAFT' rejected"
run "test_guardrail_version_non_numeric_rejected" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    guardrail_version   = "DRAFT"
  }

  expect_failures = [var.guardrail_version]
}

# --- Boundary-pass cases ---

# Scenario: "Validation Boundaries - agent_instruction 40 characters (minimum valid)"
run "test_agent_instruction_minimum_valid_length" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "This instruction is exactly forty chars."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.instruction == "This instruction is exactly forty chars."
    error_message = "Agent instruction at minimum valid length (40 chars) must be accepted"
  }
}

# Scenario: "Validation Boundaries - agent_instruction 20000 characters (maximum valid)"
run "test_agent_instruction_maximum_valid_length" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = format("%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s", join("", [for i in range(1000) : "a"]), join("", [for i in range(1000) : "b"]), join("", [for i in range(1000) : "c"]), join("", [for i in range(1000) : "d"]), join("", [for i in range(1000) : "e"]), join("", [for i in range(1000) : "f"]), join("", [for i in range(1000) : "g"]), join("", [for i in range(1000) : "h"]), join("", [for i in range(1000) : "i"]), join("", [for i in range(1000) : "j"]), join("", [for i in range(1000) : "k"]), join("", [for i in range(1000) : "l"]), join("", [for i in range(1000) : "m"]), join("", [for i in range(1000) : "n"]), join("", [for i in range(1000) : "o"]), join("", [for i in range(1000) : "p"]), join("", [for i in range(1000) : "q"]), join("", [for i in range(1000) : "r"]), join("", [for i in range(1000) : "s"]), join("", [for i in range(1000) : "t"]))
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = length(aws_bedrockagent_agent.this.instruction) == 20000
    error_message = "Agent instruction at maximum valid length (20000 chars) must be accepted"
  }
}

# Scenario: "Validation Boundaries - idle_session_ttl 60 (minimum valid)"
run "test_idle_session_ttl_minimum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    idle_session_ttl    = 60
  }

  assert {
    condition     = aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 60
    error_message = "Idle session TTL at minimum valid value (60) must be accepted"
  }
}

# Scenario: "Validation Boundaries - idle_session_ttl 3600 (maximum valid)"
run "test_idle_session_ttl_maximum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    idle_session_ttl    = 3600
  }

  assert {
    condition     = aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 3600
    error_message = "Idle session TTL at maximum valid value (3600) must be accepted"
  }
}

# Scenario: "Validation Boundaries - memory_storage_days 0 (minimum valid)"
run "test_memory_storage_days_minimum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    memory_storage_days = 0
  }

  assert {
    condition     = var.memory_storage_days == 0
    error_message = "Memory storage days at minimum valid value (0) must be accepted"
  }
}

# Scenario: "Validation Boundaries - memory_storage_days 30 (maximum valid)"
run "test_memory_storage_days_maximum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    memory_storage_days = 30
  }

  assert {
    condition     = var.memory_storage_days == 30
    error_message = "Memory storage days at maximum valid value (30) must be accepted"
  }
}

# Scenario: "Validation Boundaries - log_retention_days 1 (minimum valid CloudWatch value)"
run "test_log_retention_days_minimum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    log_retention_days  = 1
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 1
    error_message = "Log retention days at minimum valid CloudWatch value (1) must be accepted"
  }
}

# Scenario: "Validation Boundaries - api_throttle_rate_limit 1 (minimum valid)"
run "test_api_throttle_rate_limit_minimum_valid" {
  command = plan

  variables {
    agent_name              = "test-agent"
    foundation_model_id     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction       = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment             = "dev"
    owner                   = "platform-team"
    cost_center             = "CC-1234"
    api_throttle_rate_limit = 1
  }

  assert {
    condition     = var.api_throttle_rate_limit == 1
    error_message = "API throttle rate limit at minimum valid value (1) must be accepted"
  }
}

# Scenario: "Validation Boundaries - api_throttle_rate_limit 10000 (maximum valid)"
run "test_api_throttle_rate_limit_maximum_valid" {
  command = plan

  variables {
    agent_name              = "test-agent"
    foundation_model_id     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction       = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment             = "dev"
    owner                   = "platform-team"
    cost_center             = "CC-1234"
    api_throttle_rate_limit = 10000
  }

  assert {
    condition     = var.api_throttle_rate_limit == 10000
    error_message = "API throttle rate limit at maximum valid value (10000) must be accepted"
  }
}

# Scenario: "Validation Boundaries - api_throttle_burst_limit 1 (minimum valid)"
run "test_api_throttle_burst_limit_minimum_valid" {
  command = plan

  variables {
    agent_name               = "test-agent"
    foundation_model_id      = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction        = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment              = "dev"
    owner                    = "platform-team"
    cost_center              = "CC-1234"
    api_throttle_burst_limit = 1
  }

  assert {
    condition     = var.api_throttle_burst_limit == 1
    error_message = "API throttle burst limit at minimum valid value (1) must be accepted"
  }
}

# Scenario: "Validation Boundaries - environment 'dev' accepted"
run "test_environment_dev_accepted" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Environment"] == "dev"
    error_message = "Environment 'dev' must be accepted as a valid value"
  }
}

# Scenario: "Validation Boundaries - environment 'prod' accepted"
run "test_environment_prod_accepted" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "prod"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.tags["Environment"] == "prod"
    error_message = "Environment 'prod' must be accepted as a valid value"
  }
}

# Scenario: "Validation Boundaries - agent_name 'a' (minimum valid, 1 char)"
run "test_agent_name_minimum_valid_length" {
  command = plan

  variables {
    agent_name          = "a"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
  }

  assert {
    condition     = aws_bedrockagent_agent.this.agent_name == "a"
    error_message = "Agent name at minimum valid length (1 char) must be accepted"
  }
}

# Scenario: "Validation Boundaries - guardrail_version '1' (minimum valid numeric string)"
run "test_guardrail_version_minimum_valid" {
  command = plan

  variables {
    agent_name          = "test-agent"
    foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
    agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise."
    environment         = "dev"
    owner               = "platform-team"
    cost_center         = "CC-1234"
    guardrail_version   = "1"
  }

  assert {
    condition     = var.guardrail_version == "1"
    error_message = "Guardrail version '1' (single-digit numeric string) must be accepted"
  }
}
