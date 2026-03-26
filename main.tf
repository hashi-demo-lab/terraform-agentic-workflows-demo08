#------------------------------------------------------------------------------
# Core Bedrock Agent Resources
#
# - Agent: always created, orchestrates foundation model, action groups, and KBs.
# - Code Interpreter action group: conditional on var.enable_code_interpreter.
# - Custom action groups: for_each over var.action_group_definitions.
# - Agent alias "live": always created, triggers preparation (AD-3).
# - CloudWatch log group: always created, encrypted with KMS (NFR-2).
#------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Bedrock Agent
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent" "this" {
  agent_name                  = var.agent_name
  agent_resource_role_arn     = aws_iam_role.agent.arn
  foundation_model            = var.foundation_model_id
  instruction                 = var.agent_instruction
  customer_encryption_key_arn = local.effective_kms_key_arn
  idle_session_ttl_in_seconds = var.idle_session_ttl
  prepare_agent               = false
  skip_resource_in_use_check  = true

  dynamic "guardrail_configuration" {
    for_each = local.has_guardrail ? [1] : []

    content {
      guardrail_identifier = local.effective_guardrail_id
      guardrail_version    = local.effective_guardrail_version
    }
  }

  dynamic "memory_configuration" {
    for_each = var.enable_memory ? [1] : []

    content {
      enabled_memory_types = ["SESSION_SUMMARY"]
      storage_days         = var.memory_storage_days
    }
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.agent]
}

# -----------------------------------------------------------------------------
# Code Interpreter Action Group (built-in)
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent_action_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  action_group_name             = "CodeInterpreter"
  agent_id                      = aws_bedrockagent_agent.this.agent_id
  agent_version                 = "DRAFT"
  parent_action_group_signature = "AMAZON.CodeInterpreter"
  prepare_agent                 = false
  skip_resource_in_use_check    = true
}

# -----------------------------------------------------------------------------
# Custom Action Groups
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent_action_group" "custom" {
  for_each = local.action_group_map

  action_group_name          = each.value.name
  description                = each.value.description
  agent_id                   = aws_bedrockagent_agent.this.agent_id
  agent_version              = "DRAFT"
  prepare_agent              = false
  skip_resource_in_use_check = true

  dynamic "action_group_executor" {
    for_each = each.value.lambda_arn != null ? [1] : []

    content {
      lambda = each.value.lambda_arn
    }
  }

  dynamic "action_group_executor" {
    for_each = each.value.custom_control != null ? [1] : []

    content {
      custom_control = each.value.custom_control
    }
  }

  dynamic "api_schema" {
    for_each = each.value.api_schema_payload != null ? [1] : []

    content {
      payload = each.value.api_schema_payload
    }
  }

  dynamic "api_schema" {
    for_each = each.value.api_schema_s3_bucket != null ? [1] : []

    content {
      s3 {
        s3_bucket_name = each.value.api_schema_s3_bucket
        s3_object_key  = each.value.api_schema_s3_key
      }
    }
  }

  dynamic "function_schema" {
    for_each = each.value.function_schema != null ? [each.value.function_schema] : []

    content {
      member_functions {
        dynamic "functions" {
          for_each = function_schema.value

          content {
            name        = functions.value.name
            description = try(functions.value.description, null)

            dynamic "parameters" {
              for_each = try(functions.value.parameters, {})

              content {
                map_block_key = parameters.key
                type          = parameters.value.type
                description   = try(parameters.value.description, null)
                required      = try(parameters.value.required, false)
              }
            }
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Agent Alias (triggers preparation -- must be created LAST per AD-3)
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent_alias" "this" {
  agent_alias_name = "live"
  agent_id         = aws_bedrockagent_agent.this.agent_id
  description      = "Live alias for ${var.agent_name}"

  tags = local.tags

  depends_on = [
    aws_bedrockagent_agent_action_group.code_interpreter,
    aws_bedrockagent_agent_action_group.custom,
    aws_bedrockagent_agent_knowledge_base_association.this,
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group (always created, encrypted -- NFR-2)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/bedrock/agent/${var.agent_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.effective_kms_key_arn

  tags = local.tags
}
