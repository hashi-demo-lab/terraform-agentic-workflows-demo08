locals {
  # Required tags merged with consumer-provided tags.
  # Consumer tags take precedence via merge ordering (last map wins on duplicates).
  required_tags = {
    Name        = var.agent_name
    ManagedBy   = "terraform"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Project     = var.agent_name
    Application = var.agent_name
  }

  tags = merge(local.required_tags, var.tags)

  # Effective KMS key ARN: use BYO key if provided, otherwise use module-created key.
  effective_kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : try(aws_kms_key.this[0].arn, null)

  # Effective guardrail references: use BYO ID/version if provided, module-created if
  # guardrail_config is set, or null if no guardrail is configured.
  effective_guardrail_id      = var.guardrail_id != null ? var.guardrail_id : try(aws_bedrock_guardrail.this[0].guardrail_id, null)
  effective_guardrail_version = var.guardrail_version != null ? var.guardrail_version : try(tostring(aws_bedrock_guardrail_version.this[0].version), null)

  # Derived values for IAM policy ARN construction
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
  partition  = data.aws_partition.current.partition

  # Conditional flags for resource creation
  create_kms_key   = var.kms_key_arn == null
  create_guardrail = var.guardrail_config != null

  # Action groups with Lambda ARNs (for Lambda permission resources)
  lambda_action_groups = {
    for ag in var.action_group_definitions : ag.name => ag
    if ag.lambda_arn != null
  }

  # Action groups as a map keyed by name (for for_each on custom action groups)
  action_group_map = {
    for ag in var.action_group_definitions : ag.name => ag
  }

  # Whether a guardrail (BYO or module-created) should be associated with the agent
  has_guardrail = var.guardrail_id != null || var.guardrail_config != null
}
