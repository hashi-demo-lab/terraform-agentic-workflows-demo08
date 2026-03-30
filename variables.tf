variable "agent_name" {
  type        = string
  description = "Name of the Bedrock Agent. Alphanumeric, hyphens, and underscores only."

  validation {
    condition     = length(var.agent_name) >= 1 && length(var.agent_name) <= 100 && can(regex("^[a-zA-Z0-9_-]+$", var.agent_name))
    error_message = "agent_name must be 1-100 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "foundation_model_id" {
  type        = string
  description = "Foundation model identifier (e.g., \"anthropic.claude-3-5-sonnet-20241022-v2:0\"). Model access must be enabled in the account."

  validation {
    condition     = length(var.foundation_model_id) >= 1
    error_message = "foundation_model_id must not be empty."
  }
}

variable "agent_instruction" {
  type        = string
  description = "Instruction prompt defining agent behavior. Must be 40-20000 characters."

  validation {
    condition     = length(var.agent_instruction) >= 40 && length(var.agent_instruction) <= 20000
    error_message = "agent_instruction must be between 40 and 20000 characters."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name. Must be one of: dev, staging, prod."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  type        = string
  description = "Team or individual responsible for this agent. Used in Owner tag."

  validation {
    condition     = length(var.owner) >= 1
    error_message = "owner must not be empty."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center code for billing attribution. Used in CostCenter tag."

  validation {
    condition     = length(var.cost_center) >= 1
    error_message = "cost_center must not be empty."
  }
}

variable "idle_session_ttl" {
  type        = number
  description = "Idle session timeout in seconds. Agent sessions are terminated after this period of inactivity."
  default     = 600

  validation {
    condition     = var.idle_session_ttl >= 60 && var.idle_session_ttl <= 3600
    error_message = "idle_session_ttl must be between 60 and 3600 seconds."
  }
}

variable "enable_code_interpreter" {
  type        = bool
  description = "Enable the code interpreter sandbox for Python code execution."
  default     = true
}

variable "enable_memory" {
  type        = bool
  description = "Enable conversation memory with session summaries for context persistence across sessions."
  default     = false
}

variable "memory_storage_days" {
  type        = number
  description = "Number of days to retain conversation memory. Only used when memory is enabled."
  default     = 30

  validation {
    condition     = var.memory_storage_days >= 0 && var.memory_storage_days <= 30
    error_message = "memory_storage_days must be between 0 and 30."
  }
}

variable "enable_knowledge_base" {
  type        = bool
  description = "Enable knowledge base for retrieval-augmented generation. Requires opensearch_collection_arn and knowledge_base_s3_bucket_arn."
  default     = false
}

variable "knowledge_base_s3_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket containing knowledge base source documents. Required when enable_knowledge_base is true."
  default     = null

  validation {
    condition     = var.knowledge_base_s3_bucket_arn == null || can(regex("^arn:aws:s3:::", var.knowledge_base_s3_bucket_arn))
    error_message = "knowledge_base_s3_bucket_arn must be a valid S3 bucket ARN (arn:aws:s3:::...)."
  }
}

variable "knowledge_base_embedding_model" {
  type        = string
  description = "Embedding model for knowledge base vector generation."
  default     = "amazon.titan-embed-text-v2:0"

  validation {
    condition     = contains(["amazon.titan-embed-text-v2:0", "amazon.titan-embed-text-v1", "cohere.embed-english-v3", "cohere.embed-multilingual-v3"], var.knowledge_base_embedding_model)
    error_message = "knowledge_base_embedding_model must be one of: amazon.titan-embed-text-v2:0, amazon.titan-embed-text-v1, cohere.embed-english-v3, cohere.embed-multilingual-v3."
  }
}

variable "knowledge_base_description" {
  type        = string
  description = "Description of the knowledge base purpose. The agent uses this description to decide when to query the knowledge base."
  default     = "Knowledge base for agent context"

  validation {
    condition     = length(var.knowledge_base_description) >= 1 && length(var.knowledge_base_description) <= 200
    error_message = "knowledge_base_description must be between 1 and 200 characters."
  }
}

variable "opensearch_collection_arn" {
  type        = string
  description = "ARN of the OpenSearch Serverless collection for knowledge base vector storage. Required when enable_knowledge_base is true."
  default     = null

  validation {
    condition     = var.opensearch_collection_arn == null || can(regex("^arn:aws:aoss:", var.opensearch_collection_arn))
    error_message = "opensearch_collection_arn must be a valid OpenSearch Serverless collection ARN (arn:aws:aoss:...)."
  }
}

variable "opensearch_vector_index_name" {
  type        = string
  description = "Name of the vector index in the OpenSearch Serverless collection."
  default     = "bedrock-knowledge-base-default-index"

  validation {
    condition     = length(var.opensearch_vector_index_name) >= 1
    error_message = "opensearch_vector_index_name must not be empty."
  }
}

variable "action_group_definitions" {
  type = list(object({
    name                 = string
    description          = optional(string, "")
    lambda_arn           = optional(string)
    custom_control       = optional(string)
    api_schema_payload   = optional(string)
    api_schema_s3_bucket = optional(string)
    api_schema_s3_key    = optional(string)
    function_schema      = optional(any)
  }))
  description = "List of action group definitions. Each must specify either lambda_arn or custom_control for execution, and optionally api_schema or function_schema for the API contract."
  default     = []
}

variable "enable_api_gateway" {
  type        = bool
  description = "Enable an HTTP API Gateway endpoint for external agent invocation with IAM authorization."
  default     = false
}

variable "api_throttle_rate_limit" {
  type        = number
  description = "API Gateway steady-state request rate limit (requests per second)."
  default     = 100

  validation {
    condition     = var.api_throttle_rate_limit >= 1 && var.api_throttle_rate_limit <= 10000
    error_message = "api_throttle_rate_limit must be between 1 and 10000."
  }
}

variable "api_throttle_burst_limit" {
  type        = number
  description = "API Gateway burst request limit (concurrent requests)."
  default     = 50

  validation {
    condition     = var.api_throttle_burst_limit >= 1 && var.api_throttle_burst_limit <= 5000
    error_message = "api_throttle_burst_limit must be between 1 and 5000."
  }
}

variable "guardrail_id" {
  type        = string
  description = "ID of an existing Bedrock Guardrail to associate with the agent. Mutually exclusive with guardrail_config."
  default     = null

  validation {
    condition     = var.guardrail_id == null || length(var.guardrail_id) >= 1
    error_message = "guardrail_id must not be empty when provided."
  }
}

variable "guardrail_version" {
  type        = string
  description = "Version number of the existing guardrail. Required when guardrail_id is provided."
  default     = null

  validation {
    condition     = var.guardrail_version == null || can(regex("^[0-9]+$", var.guardrail_version))
    error_message = "guardrail_version must be a numeric string (e.g., \"1\", \"42\")."
  }
}

variable "guardrail_config" {
  type = object({
    name                      = string
    blocked_input_messaging   = optional(string, "Sorry, I cannot process that request.")
    blocked_outputs_messaging = optional(string, "Sorry, I cannot provide that response.")
    content_filters = optional(list(object({
      type            = string
      input_strength  = optional(string, "HIGH")
      output_strength = optional(string, "HIGH")
    })), [])
    topic_denials = optional(list(object({
      name       = string
      definition = string
      examples   = optional(list(string), [])
    })), [])
    pii_filters = optional(list(object({
      type   = string
      action = optional(string, "BLOCK")
    })), [])
  })
  description = "Configuration to create a new guardrail. Mutually exclusive with guardrail_id."
  default     = null
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of an existing KMS key for encryption at rest. If null, the module creates a KMS key with proper Bedrock service grants."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN (arn:aws:kms:...)."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log group retention period in days. Must be a valid CloudWatch retention value."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all taggable resources. Merged with required tags; consumer tags take precedence."
  default     = {}
}
