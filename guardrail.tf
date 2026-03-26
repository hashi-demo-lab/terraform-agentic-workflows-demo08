#------------------------------------------------------------------------------
# Guardrail Resources (conditional on var.guardrail_config != null)
#
# - Guardrail: content filtering, topic denial, and PII detection policies.
# - Guardrail version: immutable snapshot for production use.
#------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Guardrail
# -----------------------------------------------------------------------------

resource "aws_bedrock_guardrail" "this" {
  count = local.create_guardrail ? 1 : 0

  name                      = var.guardrail_config.name
  blocked_input_messaging   = var.guardrail_config.blocked_input_messaging
  blocked_outputs_messaging = var.guardrail_config.blocked_outputs_messaging
  kms_key_arn               = local.effective_kms_key_arn

  dynamic "content_policy_config" {
    for_each = length(var.guardrail_config.content_filters) > 0 ? [1] : []

    content {
      dynamic "filters_config" {
        for_each = var.guardrail_config.content_filters

        content {
          type            = filters_config.value.type
          input_strength  = filters_config.value.input_strength
          output_strength = filters_config.value.output_strength
        }
      }
    }
  }

  dynamic "topic_policy_config" {
    for_each = length(var.guardrail_config.topic_denials) > 0 ? [1] : []

    content {
      dynamic "topics_config" {
        for_each = var.guardrail_config.topic_denials

        content {
          name       = topics_config.value.name
          definition = topics_config.value.definition
          type       = "DENY"
          examples   = topics_config.value.examples
        }
      }
    }
  }

  dynamic "sensitive_information_policy_config" {
    for_each = length(var.guardrail_config.pii_filters) > 0 ? [1] : []

    content {
      dynamic "pii_entities_config" {
        for_each = var.guardrail_config.pii_filters

        content {
          type   = pii_entities_config.value.type
          action = pii_entities_config.value.action
        }
      }
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Guardrail Version (immutable snapshot)
# -----------------------------------------------------------------------------

resource "aws_bedrock_guardrail_version" "this" {
  count = local.create_guardrail ? 1 : 0

  guardrail_arn = aws_bedrock_guardrail.this[0].guardrail_arn
  description   = "Version for ${var.guardrail_config.name}"
  skip_destroy  = true
}
