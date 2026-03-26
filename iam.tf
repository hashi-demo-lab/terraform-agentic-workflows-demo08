#------------------------------------------------------------------------------
# IAM Roles and Policies for Bedrock Agent
#
# - Agent execution role: always created, trust policy for bedrock.amazonaws.com
#   with confused-deputy protections (aws:SourceAccount).
# - Agent inline policy: least-privilege bedrock:InvokeModel scoped to the
#   specific foundation model, with conditional statements for KB and guardrails.
# - Knowledge base role: conditional on var.enable_knowledge_base.
# - Lambda permissions: for_each over action groups that have lambda_arn set.
#------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Agent IAM Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "agent_trust" {
  statement {
    sid     = "AllowBedrockAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "bedrock-agent-${var.agent_name}"
  assume_role_policy = data.aws_iam_policy_document.agent_trust.json

  tags = local.tags
}

data "aws_iam_policy_document" "agent_permissions" {
  # Invoke the specified foundation model
  statement {
    sid    = "AllowInvokeModel"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel",
    ]

    resources = [
      "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.foundation_model_id}",
    ]
  }

  # Conditional: Retrieve from knowledge base
  dynamic "statement" {
    for_each = var.enable_knowledge_base ? [1] : []

    content {
      sid    = "AllowKnowledgeBaseRetrieve"
      effect = "Allow"

      actions = [
        "bedrock:Retrieve",
      ]

      resources = [
        "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*",
      ]
    }
  }

  # Conditional: Apply guardrail
  dynamic "statement" {
    for_each = local.has_guardrail ? [1] : []

    content {
      sid    = "AllowApplyGuardrail"
      effect = "Allow"

      actions = [
        "bedrock:ApplyGuardrail",
      ]

      resources = [
        "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:guardrail/*",
      ]
    }
  }

  # KMS permissions for encryption/decryption
  statement {
    sid    = "AllowKMSAccess"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [
      local.effective_kms_key_arn,
    ]
  }
}

resource "aws_iam_role_policy" "agent" {
  name   = "bedrock-agent-${var.agent_name}"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_permissions.json
}

# -----------------------------------------------------------------------------
# Knowledge Base IAM Role (conditional)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "knowledge_base_trust" {
  count = var.enable_knowledge_base ? 1 : 0

  statement {
    sid     = "AllowBedrockAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name               = "bedrock-kb-${var.agent_name}"
  assume_role_policy = data.aws_iam_policy_document.knowledge_base_trust[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "knowledge_base_permissions" {
  count = var.enable_knowledge_base ? 1 : 0

  # Invoke the embedding model
  statement {
    sid    = "AllowInvokeEmbeddingModel"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel",
    ]

    resources = [
      "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.knowledge_base_embedding_model}",
    ]
  }

  # OpenSearch Serverless API access
  statement {
    sid    = "AllowOpenSearchServerlessAccess"
    effect = "Allow"

    actions = [
      "aoss:APIAccessAll",
    ]

    resources = [
      var.opensearch_collection_arn,
    ]
  }

  # S3 access for knowledge base data source
  statement {
    sid    = "AllowS3DataSourceAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      var.knowledge_base_s3_bucket_arn,
      "${var.knowledge_base_s3_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "bedrock-kb-${var.agent_name}"
  role   = aws_iam_role.knowledge_base[0].id
  policy = data.aws_iam_policy_document.knowledge_base_permissions[0].json
}

# -----------------------------------------------------------------------------
# Lambda Permissions for Action Groups
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "action_group" {
  for_each = local.lambda_action_groups

  statement_id  = "AllowBedrockAgentInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_arn
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.this.agent_arn
}
