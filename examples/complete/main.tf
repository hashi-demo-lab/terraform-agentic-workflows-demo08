# Complete Example: Bedrock Agent with All Features Enabled
#
# This example demonstrates every configurable feature of the module:
#   - Code interpreter (enabled by default)
#   - Conversation memory with custom retention
#   - Knowledge base backed by S3 and OpenSearch Serverless
#   - Custom action group with Lambda and API schema
#   - API Gateway endpoint with throttling
#   - Content-filtering guardrail with PII protection
#   - Custom log retention
#   - Custom tags
#
# Prerequisites:
#   - Foundation model access enabled in the account
#   - An existing OpenSearch Serverless collection for vector storage
#   - An existing S3 bucket with knowledge base source documents
#   - An existing Lambda function for the action group

provider "aws" {
  region = var.region
}

module "bedrock_agent" {
  source = "../../"

  # -------------------------------------------------------------------------
  # Core agent configuration
  # -------------------------------------------------------------------------
  agent_name          = "complete-assistant"
  foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  agent_instruction   = "You are an advanced enterprise assistant that helps employees find information in the company knowledge base, execute data analysis tasks, and interact with internal APIs. Always cite your sources when retrieving information from the knowledge base."
  idle_session_ttl    = 800 # 30 minutes

  # -------------------------------------------------------------------------
  # Code interpreter (enabled by default, shown explicitly for clarity)
  # -------------------------------------------------------------------------
  enable_code_interpreter = true

  # -------------------------------------------------------------------------
  # Conversation memory -- retain session summaries for 14 days
  # -------------------------------------------------------------------------
  enable_memory       = true
  memory_storage_days = 14

  # -------------------------------------------------------------------------
  # Knowledge base -- RAG with S3 documents and OpenSearch vector store
  # Replace ARNs with your actual resources.
  # -------------------------------------------------------------------------
  enable_knowledge_base          = true
  knowledge_base_s3_bucket_arn   = "arn:aws:s3:::my-company-knowledge-docs"
  opensearch_collection_arn      = "arn:aws:aoss:us-east-1:123456789012:collection/abc123def456"
  knowledge_base_embedding_model = "amazon.titan-embed-text-v2:0"
  knowledge_base_description     = "Company policy documents, runbooks, and technical documentation"
  opensearch_vector_index_name   = "bedrock-knowledge-base-default-index"

  # -------------------------------------------------------------------------
  # Action groups -- Lambda-backed tool with an OpenAPI schema
  # Replace the Lambda ARN with your deployed function.
  # -------------------------------------------------------------------------
  action_group_definitions = [
    {
      name        = "TicketManager"
      description = "Creates, updates, and queries support tickets in the internal ticketing system"
      lambda_arn  = "arn:aws:lambda:us-east-1:123456789012:function:ticket-manager"
      api_schema_payload = jsonencode({
        openapi = "3.0.0"
        info = {
          title   = "Ticket Manager API"
          version = "1.0.0"
        }
        paths = {
          "/tickets" = {
            get = {
              operationId = "listTickets"
              summary     = "List open support tickets"
              parameters = [
                {
                  name     = "status"
                  in       = "query"
                  required = false
                  schema   = { type = "string", enum = ["open", "closed", "in_progress"] }
                }
              ]
              responses = {
                "200" = { description = "List of tickets" }
              }
            }
            post = {
              operationId = "createTicket"
              summary     = "Create a new support ticket"
              requestBody = {
                required = true
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        title       = { type = "string" }
                        description = { type = "string" }
                        priority    = { type = "string", enum = ["low", "medium", "high"] }
                      }
                      required = ["title", "description"]
                    }
                  }
                }
              }
              responses = {
                "201" = { description = "Ticket created" }
              }
            }
          }
        }
      })
    }
  ]

  # -------------------------------------------------------------------------
  # API Gateway -- expose the agent via HTTP with IAM authorization
  # -------------------------------------------------------------------------
  enable_api_gateway       = true
  api_throttle_rate_limit  = 200
  api_throttle_burst_limit = 100

  # -------------------------------------------------------------------------
  # Guardrail -- content filters and PII protection
  # -------------------------------------------------------------------------
  guardrail_config = {
    name                      = "complete-assistant-guardrail"
    blocked_input_messaging   = "Your request contains content that is not permitted by company policy."
    blocked_outputs_messaging = "The response was blocked due to content policy restrictions."

    content_filters = [
      {
        type            = "SEXUAL"
        input_strength  = "HIGH"
        output_strength = "HIGH"
      },
      {
        type            = "VIOLENCE"
        input_strength  = "HIGH"
        output_strength = "HIGH"
      },
      {
        type            = "HATE"
        input_strength  = "HIGH"
        output_strength = "HIGH"
      },
      {
        type            = "INSULTS"
        input_strength  = "MEDIUM"
        output_strength = "HIGH"
      },
      {
        type            = "MISCONDUCT"
        input_strength  = "HIGH"
        output_strength = "HIGH"
      },
      {
        type            = "PROMPT_ATTACK"
        input_strength  = "HIGH"
        output_strength = "NONE"
      },
    ]

    topic_denials = [
      {
        name       = "CompetitorDiscussion"
        definition = "Discussions that compare our products unfavorably to competitors or recommend competitor products"
        examples   = ["Which competitor product is better?", "Why should I switch to a competitor?"]
      },
    ]

    pii_filters = [
      {
        type   = "US_SOCIAL_SECURITY_NUMBER"
        action = "BLOCK"
      },
      {
        type   = "CREDIT_DEBIT_CARD_NUMBER"
        action = "BLOCK"
      },
      {
        type   = "EMAIL"
        action = "ANONYMIZE"
      },
    ]
  }

  # -------------------------------------------------------------------------
  # Encryption -- use the module-created KMS key (default)
  # To bring your own KMS key, uncomment the line below:
  # kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  # -------------------------------------------------------------------------

  # -------------------------------------------------------------------------
  # Logging -- 365-day retention for compliance
  # -------------------------------------------------------------------------
  log_retention_days = 365

  # -------------------------------------------------------------------------
  # Tagging -- required tags plus custom tags
  # -------------------------------------------------------------------------
  environment = "prod"
  owner       = "ml-platform-team"
  cost_center = "CC-5678"

  tags = {
    Team        = "ML Platform"
    Compliance  = "SOC2"
    DataClass   = "Confidential"
    CostProject = "bedrock-agent-pilot"
  }
}
