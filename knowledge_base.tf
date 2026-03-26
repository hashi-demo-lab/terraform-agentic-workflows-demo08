#------------------------------------------------------------------------------
# Knowledge Base Resources (conditional on var.enable_knowledge_base)
#
# - Knowledge base: VECTOR type with OpenSearch Serverless storage backend.
# - Data source: S3-backed with server-side encryption.
# - Agent association: links the KB to the agent for RAG queries.
#------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Knowledge Base
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_knowledge_base" "this" {
  count = var.enable_knowledge_base ? 1 : 0

  name        = "${var.agent_name}-kb"
  role_arn    = aws_iam_role.knowledge_base[0].arn
  description = var.knowledge_base_description

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.knowledge_base_embedding_model}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = var.opensearch_collection_arn
      vector_index_name = var.opensearch_vector_index_name

      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.knowledge_base]
}

# -----------------------------------------------------------------------------
# Data Source (S3-backed)
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_data_source" "this" {
  count = var.enable_knowledge_base ? 1 : 0

  name              = "${var.agent_name}-datasource"
  knowledge_base_id = aws_bedrockagent_knowledge_base.this[0].id

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = var.knowledge_base_s3_bucket_arn
    }
  }

  server_side_encryption_configuration {
    kms_key_arn = local.effective_kms_key_arn
  }
}

# -----------------------------------------------------------------------------
# Agent-Knowledge Base Association
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_agent_knowledge_base_association" "this" {
  count = var.enable_knowledge_base ? 1 : 0

  agent_id             = aws_bedrockagent_agent.this.agent_id
  description          = var.knowledge_base_description
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this[0].id
  knowledge_base_state = "ENABLED"
}
