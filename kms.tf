#------------------------------------------------------------------------------
# KMS Key and Alias for Bedrock Agent Encryption
#
# Creates a customer-managed KMS key with service grants for bedrock.amazonaws.com
# and logs.amazonaws.com when no external key ARN is provided (var.kms_key_arn == null).
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_key_policy" {
  count = local.create_kms_key ? 1 : 0

  # Root account full access
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Bedrock service access
  statement {
    sid    = "AllowBedrockServiceAccess"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    resources = ["*"]
  }

  # CloudWatch Logs service access for log encryption
  statement {
    sid    = "AllowCloudWatchLogsAccess"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock/agent/${var.agent_name}"]
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encryption key for Bedrock Agent ${var.agent_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_key_policy[0].json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/bedrock-agent-${var.agent_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
