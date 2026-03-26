## Research: AWS Bedrock AgentCore Best Practices, Security Patterns, and Architectural Guidance

### Decision

Deploy Bedrock AgentCore infrastructure using a layered security approach: least-privilege IAM with dual service principals (`bedrock.amazonaws.com` for Bedrock Agents and `bedrock-agentcore.amazonaws.com` for AgentCore runtimes/gateways), customer-managed KMS encryption across all supported resources, CloudWatch invocation logging, guardrails with content and topic filtering, and AgentCore Gateway with JWT or IAM authorization for external access.

---

### 1. IAM Best Practices for Bedrock Agents

#### Agent Execution Role (Bedrock Agents)

The `agent_resource_role_arn` on `aws_bedrockagent_agent` requires a trust policy for `bedrock.amazonaws.com` with confused-deputy protections:

```hcl
data "aws_iam_policy_document" "agent_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }
    condition {
      test     = "ArnLike"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:agent/*"]
      variable = "AWS:SourceArn"
    }
  }
}
```

**Key permissions for the agent execution role:**

| Permission | Resource ARN Pattern | Purpose |
|---|---|---|
| `bedrock:InvokeModel` | `arn:aws:bedrock:{region}::foundation-model/{model-id}` | Invoke specific foundation model |
| `bedrock:Retrieve` | `arn:aws:bedrock:{region}:{account}:knowledge-base/{kb-id}` | Query knowledge base |
| `bedrock:ApplyGuardrail` | `arn:aws:bedrock:{region}:{account}:guardrail/{guardrail-id}` | Apply guardrails |
| `lambda:InvokeFunction` | `arn:aws:lambda:{region}:{account}:function:{fn-name}` | Invoke action group Lambda |
| `s3:GetObject` | `arn:aws:s3:::{bucket}/{prefix}/*` | Access API schemas in S3 |

**Model ARN scoping** -- Always scope `bedrock:InvokeModel` to specific model ARNs, not `*`. Foundation model ARNs follow the pattern: `arn:aws:bedrock:{region}::foundation-model/{provider}.{model-name}`. The double-colon (`::`) indicates these are AWS-owned resources with no account ID.

**IAM naming convention**: AWS documentation recommends the prefix `AmazonBedrockExecutionRoleForAgents_` for agent execution roles.

#### AgentCore Runtime/Gateway Role

AgentCore resources (`aws_bedrockagentcore_agent_runtime`, `aws_bedrockagentcore_gateway`, `aws_bedrockagentcore_browser`, `aws_bedrockagentcore_code_interpreter`) use the service principal `bedrock-agentcore.amazonaws.com`:

```hcl
data "aws_iam_policy_document" "agentcore_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}
```

**Additional permissions for AgentCore runtimes with ECR containers:**
- `ecr:GetAuthorizationToken` (resource `*`)
- `ecr:BatchGetImage` and `ecr:GetDownloadUrlForLayer` (scoped to ECR repository ARN)

**AWS managed policies for AgentCore Memory:**
- `AmazonBedrockAgentCoreMemoryBedrockModelInferenceExecutionRolePolicy` -- attach to the memory execution role when using memory strategies with model processing.

#### Lambda Invoke Permissions for Action Groups

Action groups require the Lambda function ARN in `action_group_executor.lambda`. The agent execution role needs `lambda:InvokeFunction` on the specific function ARN. Additionally, the Lambda needs a resource-based policy allowing Bedrock to invoke it.

#### Knowledge Base Role

The `role_arn` on `aws_bedrockagent_knowledge_base` needs permissions for:
- `bedrock:InvokeModel` on the embedding model (e.g., `amazon.titan-embed-text-v2:0`)
- `aoss:APIAccessAll` on the OpenSearch Serverless collection (for vector store)
- `s3:GetObject`, `s3:ListBucket` on data source S3 buckets

---

### 2. KMS Encryption

#### Resources Supporting Customer-Managed KMS Keys

| Resource | KMS Argument | Purpose |
|---|---|---|
| `aws_bedrockagent_agent` | `customer_encryption_key_arn` | Encrypts agent configuration and session data |
| `aws_bedrock_guardrail` | `kms_key_arn` | Encrypts guardrail configuration at rest |
| `aws_bedrockagent_data_source` | `server_side_encryption_configuration.kms_key_arn` | Encrypts data source content |
| `aws_bedrockagentcore_memory` | `encryption_key_arn` | Encrypts memory storage (events and strategies) |
| `aws_bedrockagentcore_gateway` | `kms_key_arn` | Encrypts gateway data |
| `aws_bedrockagentcore_token_vault_cmk` | `kms_configuration.kms_key_arn` | Encrypts token vault credentials |
| OpenSearch Serverless (via security policy) | `KmsARN` in encryption policy JSON | Encrypts vector store collections |

#### KMS Key Policy Requirements

The KMS key policy must grant the Bedrock service principal permissions to use the key:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "bedrock.amazonaws.com"
  },
  "Action": [
    "kms:Decrypt",
    "kms:Encrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey",
    "kms:CreateGrant"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:SourceAccount": "{account-id}"
    }
  }
}
```

For AgentCore resources, include `bedrock-agentcore.amazonaws.com` as an additional service principal.

#### Token Vault CMK

The `aws_bedrockagentcore_token_vault_cmk` resource specifically manages the CMK for the AgentCore token vault. It supports two modes:
- `CustomerManagedKey` -- use your own KMS key
- `ServiceManagedKey` -- use AWS-managed encryption

**Important**: Deletion of this resource only removes it from Terraform state; it does not modify the actual CMK.

---

### 3. CloudWatch Logging

#### Model Invocation Logging

`aws_bedrock_model_invocation_logging_configuration` is a **regional singleton** -- only one configuration per AWS region. It supports dual destinations:

**CloudWatch Logs destination:**
```hcl
logging_config {
  text_data_delivery_enabled      = true
  image_data_delivery_enabled     = true
  embedding_data_delivery_enabled = true
  video_data_delivery_enabled     = true
  cloudwatch_config {
    log_group_name = "/aws/bedrock/model-invocations"
    role_arn       = aws_iam_role.bedrock_logging.arn
    large_data_delivery_s3_config {
      bucket_name = aws_s3_bucket.bedrock_logs.id
      key_prefix  = "large-payloads"
    }
  }
}
```

**S3 destination:**
```hcl
logging_config {
  text_data_delivery_enabled      = true
  image_data_delivery_enabled     = true
  embedding_data_delivery_enabled = true
  s3_config {
    bucket_name = aws_s3_bucket.bedrock_logs.id
    key_prefix  = "bedrock"
  }
}
```

The S3 bucket policy must allow `bedrock.amazonaws.com` to write with `aws:SourceAccount` and `aws:SourceArn` conditions.

**Key logging considerations:**
- This is a **regional resource** -- should not be defined in multiple Terraform configurations for the same region
- `embedding_data_delivery_enabled` captures embedding model invocations
- `large_data_delivery_s3_config` in CloudWatch config handles overflow for large payloads
- Log data includes input/output text, model parameters, latency, and token counts

#### AgentCore Browser Session Recording

The `aws_bedrockagentcore_browser` resource supports session recording to S3 via the `recording` block:
```hcl
recording {
  enabled = true
  s3_location {
    bucket = aws_s3_bucket.recording.bucket
    prefix = "browser-sessions/"
  }
}
```

#### X-Ray Tracing

AWS Bedrock supports X-Ray tracing integration. While there is no dedicated Terraform argument for X-Ray on the agent resource itself, tracing is enabled at the AWS account/service level. Lambda functions used in action groups should have `tracing_config { mode = "Active" }` set to propagate trace context through the agent invocation chain.

---

### 4. Knowledge Base Architecture

#### OpenSearch Serverless Vector Store Requirements

A complete knowledge base with OpenSearch Serverless requires four coordinated resources:

1. **Encryption Security Policy** (`aws_opensearchserverless_security_policy`, type `encryption`):
   - Must exist BEFORE the collection (use `depends_on`)
   - Can use AWS-owned key (`AWSOwnedKey = true`) or customer-managed KMS key

2. **Network Security Policy** (`aws_opensearchserverless_security_policy`, type `network`):
   - `AllowFromPublic = true` or VPC endpoint access via `SourceVPCEs`
   - Must cover both `collection` and `dashboard` resource types

3. **OpenSearch Serverless Collection** (`aws_opensearchserverless_collection`):
   - `type = "VECTORSEARCH"` for knowledge base use
   - `standby_replicas` can be `DISABLED` for dev (cost savings) or `ENABLED` for production
   - Create/delete timeout: 20 minutes

4. **Data Access Policy** (`aws_opensearchserverless_access_policy`, type `data`):
   - Must grant `aoss:*` on both `collection/{name}` and `index/{name}/*`
   - Principal must include both the Bedrock KB role ARN and the Terraform execution role

#### Knowledge Base Configuration

```hcl
resource "aws_bedrockagent_knowledge_base" "example" {
  name     = "example"
  role_arn = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0"
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.example.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}
```

#### Embedding Model Options

| Model | Dimensions | Notes |
|---|---|---|
| `amazon.titan-embed-text-v2:0` | 256, 512, 1024 | Configurable dimensions, recommended default |
| `amazon.titan-embed-text-v1` | 1536 | Legacy, fixed dimension |
| `cohere.embed-english-v3` | 1024 | English-optimized |
| `cohere.embed-multilingual-v3` | 1024 | Multilingual support |

Embedding data types: `FLOAT32` (default, full precision) or `BINARY` (compact, lower precision).

#### Supported Vector Store Types

`storage_configuration.type` valid values: `OPENSEARCH_SERVERLESS`, `OPENSEARCH_MANAGED_CLUSTER`, `PINECONE`, `REDIS_ENTERPRISE_CLOUD`, `RDS`, `MONGO_DB_ATLAS`, `S3_VECTORS`, `NEPTUNE_ANALYTICS`.

#### Data Source and Chunking Strategies

`aws_bedrockagent_data_source` supports S3, Web, Confluence, Salesforce, SharePoint, and Custom sources.

**Chunking strategies** (set on `vector_ingestion_configuration.chunking_configuration`):

| Strategy | Use Case | Key Parameters |
|---|---|---|
| `FIXED_SIZE` | General purpose, predictable chunks | `max_tokens` (e.g., 512), `overlap_percentage` (e.g., 20) |
| `HIERARCHICAL` | Documents with natural hierarchy | Two `level_configuration` blocks with `max_tokens`, plus `overlap_tokens` |
| `SEMANTIC` | Context-aware splitting | `breakpoint_percentile_threshold`, `buffer_size`, `max_token` |
| `NONE` | Pre-chunked data or short documents | No parameters |

**Parsing strategies:**
- `BEDROCK_FOUNDATION_MODEL` -- Uses a foundation model (e.g., Claude) for multimodal parsing with configurable prompts
- `BEDROCK_DATA_AUTOMATION` -- Uses Bedrock Data Automation for document parsing

All chunking and parsing configuration is **forces new resource** -- changes require recreation of the data source.

---

### 5. AgentCore Gateway Integration (Replaces API Gateway Pattern)

#### AgentCore Gateway as Native HTTP Endpoint

Bedrock AgentCore introduces `aws_bedrockagentcore_gateway` as the native way to expose agents and MCP tools via HTTP -- this replaces the traditional API Gateway + Lambda proxy pattern for Bedrock agents.

**Key Gateway features:**
- Native MCP (Model Context Protocol) support
- Built-in JWT and IAM authorization
- Lambda interceptors for request/response processing
- Gateway targets for Lambda, API Gateway, MCP servers, and OpenAPI/Smithy schemas
- KMS encryption support

```hcl
resource "aws_bedrockagentcore_gateway" "example" {
  name     = "agent-gateway"
  role_arn = aws_iam_role.gateway.arn

  authorizer_type = "CUSTOM_JWT"
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = "https://auth.example.com/.well-known/openid-configuration"
      allowed_audience = ["app-client"]
      allowed_clients  = ["client-123"]
      allowed_scopes   = ["openid", "invoke"]
    }
  }

  protocol_type = "MCP"
  protocol_configuration {
    mcp {
      supported_versions = ["2025-03-26"]
      search_type        = "SEMANTIC"
    }
  }

  kms_key_arn = aws_kms_key.gateway.arn
}
```

**Authorization options:**
- `CUSTOM_JWT` -- Validate JWT tokens from an OIDC provider (discovery URL required)
- `AWS_IAM` -- Standard AWS Signature V4 authentication

**Gateway targets** (`aws_bedrockagentcore_gateway_target`) support:
- Lambda functions with inline tool schemas
- API Gateway REST APIs with tool filters
- Remote MCP servers
- OpenAPI/Smithy schema-based targets

**Credential provider configurations for targets:**
- `gateway_iam_role` -- Use the gateway's own IAM role
- `api_key` -- API key-based authentication (stored in Secrets Manager)
- `oauth` -- OAuth2/OIDC with client_credentials or authorization_code grant types

**Interceptor pattern:** Lambda interceptors can be attached at `REQUEST` and/or `RESPONSE` interception points for custom processing, logging, or transformation.

#### AgentCore Runtime Endpoint (Direct Agent Invocation)

For containerized agents, `aws_bedrockagentcore_agent_runtime_endpoint` provides a direct network endpoint:

```hcl
resource "aws_bedrockagentcore_agent_runtime_endpoint" "example" {
  name             = "prod-endpoint"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.example.agent_runtime_id
}
```

The runtime itself supports:
- Container-based (ECR image URI) or code-based (S3 + Python runtime) artifacts
- `PUBLIC` or `VPC` network modes
- JWT authorization on the runtime itself
- Protocol modes: `HTTP`, `MCP`, `A2A` (Agent-to-Agent)

#### Traditional API Gateway Pattern (Alternative)

If using traditional API Gateway v2 instead of AgentCore Gateway:
- Use `aws_apigatewayv2_api` (protocol `HTTP`)
- `aws_apigatewayv2_authorizer` for IAM or JWT authorization
- `aws_apigatewayv2_integration` with Lambda proxy to invoke `bedrock-agent-runtime:InvokeAgent`
- `aws_apigatewayv2_stage` with throttling (`default_route_settings`)

---

### 6. Guardrails

#### Content Filter Types

`aws_bedrock_guardrail` content policy `filters_config` supports these types:

| Type | Description |
|---|---|
| `HATE` | Hate speech and discriminatory content |
| `VIOLENCE` | Violent or threatening content |
| `SEXUAL` | Sexual or explicit content |
| `INSULTS` | Insulting or demeaning content |
| `MISCONDUCT` | Criminal or harmful activities |
| `PROMPT_ATTACK` | Prompt injection and jailbreak attempts |

Each filter has independent `input_strength` and `output_strength` (values: `NONE`, `LOW`, `MEDIUM`, `HIGH`) plus `input_action`/`output_action` (`BLOCK`, `NONE`).

**Tier configuration**: `STANDARD` (enhanced detection) or `CLASSIC` (original).

#### Topic Denial

```hcl
topic_policy_config {
  topics_config {
    name       = "investment_topic"
    type       = "DENY"
    definition = "Investment advice refers to guidance on allocation of funds"
    examples   = ["Where should I invest my money?"]
  }
}
```

#### Sensitive Information Filters

- **PII entities**: `NAME`, `EMAIL`, `PHONE`, `SSN`, `CREDIT_CARD_NUMBER`, etc. Actions: `BLOCK`, `ANONYMIZE`, `NONE`
- **Custom regex**: Pattern-based detection with custom names and descriptions

```hcl
sensitive_information_policy_config {
  pii_entities_config {
    type           = "NAME"
    action         = "BLOCK"
    input_action   = "BLOCK"
    output_action  = "ANONYMIZE"
    input_enabled  = true
    output_enabled = true
  }
  regexes_config {
    name           = "ssn_pattern"
    pattern        = "^\\d{3}-\\d{2}-\\d{4}$"
    action         = "BLOCK"
    input_action   = "BLOCK"
    output_action  = "BLOCK"
    input_enabled  = true
    output_enabled = true
  }
}
```

#### Word Filters

- **Managed word lists**: `PROFANITY` (AWS-curated)
- **Custom words**: Arbitrary text strings to block

#### Contextual Grounding

`contextual_grounding_policy_config` -- threshold-based filtering to ensure responses are grounded in provided context.

#### Attaching Guardrails to Agents

```hcl
resource "aws_bedrockagent_agent" "example" {
  # ...
  guardrail_configuration {
    guardrail_identifier = aws_bedrock_guardrail.example.guardrail_id
    guardrail_version    = aws_bedrock_guardrail_version.example.version
  }
}
```

**Guardrail versioning**: Use `aws_bedrock_guardrail_version` to create immutable versions. Set `skip_destroy = true` to retain old versions during updates.

---

### 7. Agent and AgentCore Lifecycle

#### Bedrock Agent Lifecycle

- `prepare_agent` argument (default `true`) -- automatically prepares the agent after creation or modification
- Agent states: `CREATING` -> `PREPARING` -> `PREPARED` (ready to invoke)
- `prepared_at` attribute indicates last preparation timestamp
- `agent_version` attribute tracks the current version

#### Alias Versioning Strategy

```hcl
resource "aws_bedrockagent_agent_alias" "prod" {
  agent_alias_name = "production"
  agent_id         = aws_bedrockagent_agent.example.agent_id

  routing_configuration {
    agent_version          = "3"  # Pin to specific version
    provisioned_throughput = aws_bedrock_provisioned_model_throughput.example.model_arn  # Optional
  }
}
```

**Best practices:**
- Create a `DRAFT` alias for development (auto-updates to latest version)
- Create numbered version aliases for production (pin to specific agent version)
- Use `routing_configuration.provisioned_throughput` for high-traffic agents

#### Session Management

- `idle_session_ttl_in_seconds` on the agent controls session timeout (default varies)
- After timeout, session data is deleted by Bedrock
- `memory_configuration` enables persistent memory across sessions:
  - `enabled_memory_types = ["SESSION_SUMMARY"]`
  - `storage_days` (0-30) controls retention
  - `session_summary_configuration.max_recent_sessions` controls context window

#### AgentCore Runtime Lifecycle

- `lifecycle_configuration.idle_runtime_session_timeout` -- timeout for idle runtime sessions (seconds)
- `lifecycle_configuration.max_lifetime` -- maximum instance lifetime (seconds)
- `network_configuration.network_mode` -- `PUBLIC` or `VPC`
- `protocol_configuration.server_protocol` -- `HTTP`, `MCP`, or `A2A`

#### AgentCore Memory Lifecycle

- `event_expiry_duration` -- 7 to 365 days for memory event retention
- Maximum 6 strategies per memory
- One built-in strategy per type (`SEMANTIC`, `SUMMARIZATION`, `USER_PREFERENCE`)
- Multiple `CUSTOM` strategies allowed (up to 6 total)

---

### Resources Identified

- **Primary Resources (Bedrock Agents)**:
  - `aws_bedrockagent_agent` -- The AI agent itself
  - `aws_bedrockagent_agent_action_group` -- Action groups with Lambda or return-control
  - `aws_bedrockagent_agent_alias` -- Versioned aliases for production routing
  - `aws_bedrockagent_agent_knowledge_base_association` -- Link agents to knowledge bases
  - `aws_bedrockagent_knowledge_base` -- Knowledge base with vector/SQL/Kendra config
  - `aws_bedrockagent_data_source` -- S3/Web/Confluence/etc. data sources

- **Primary Resources (Bedrock AgentCore)**:
  - `aws_bedrockagentcore_agent_runtime` -- Containerized agent runtime (ECR or S3+Python)
  - `aws_bedrockagentcore_agent_runtime_endpoint` -- Network endpoint for runtime
  - `aws_bedrockagentcore_gateway` -- MCP gateway with JWT/IAM auth
  - `aws_bedrockagentcore_gateway_target` -- Lambda/API Gateway/MCP server targets
  - `aws_bedrockagentcore_memory` -- Persistent agent memory
  - `aws_bedrockagentcore_memory_strategy` -- Memory processing strategies
  - `aws_bedrockagentcore_browser` -- Web browsing capability
  - `aws_bedrockagentcore_code_interpreter` -- Python code execution
  - `aws_bedrockagentcore_workload_identity` -- OAuth2 identity for agents
  - `aws_bedrockagentcore_api_key_credential_provider` -- API key credential management
  - `aws_bedrockagentcore_oauth2_credential_provider` -- OAuth2 credential management
  - `aws_bedrockagentcore_token_vault_cmk` -- Token vault encryption

- **Supporting Resources (Guardrails and Logging)**:
  - `aws_bedrock_guardrail` -- Content/topic/word/PII filters
  - `aws_bedrock_guardrail_version` -- Immutable guardrail versions
  - `aws_bedrock_model_invocation_logging_configuration` -- CloudWatch/S3 logging (regional singleton)

- **Supporting Resources (OpenSearch Serverless for Knowledge Base)**:
  - `aws_opensearchserverless_collection` -- Vector search collection
  - `aws_opensearchserverless_security_policy` -- Encryption and network policies
  - `aws_opensearchserverless_access_policy` -- Data access policies

- **Supporting Resources (IAM)**:
  - `aws_iam_role` -- Execution roles for agent, knowledge base, gateway, runtime
  - `aws_iam_role_policy` / `aws_iam_role_policy_attachment` -- Permission policies
  - `aws_iam_policy_document` -- Trust and permission policy documents

- **Key Outputs**:
  - `agent_id` (`string`), `agent_arn` (`string`), `agent_version` (`string`)
  - `agent_alias_id` (`string`), `agent_alias_arn` (`string`)
  - `knowledge_base.id` (`string`), `knowledge_base.arn` (`string`)
  - `guardrail_id` (`string`), `guardrail_arn` (`string`), `version` (`string`)
  - `gateway_id` (`string`), `gateway_arn` (`string`), `gateway_url` (`string`)
  - `agent_runtime_id` (`string`), `agent_runtime_arn` (`string`)
  - `memory.id` (`string`), `memory.arn` (`string`)
  - `collection_endpoint` (`string`), `dashboard_endpoint` (`string`)

---

### Security Considerations Summary

1. **Least-privilege IAM**: Scope model invocation to specific foundation model ARNs; scope Lambda invoke to specific function ARNs
2. **Confused deputy prevention**: Always include `aws:SourceAccount` and `aws:SourceArn` conditions on trust policies
3. **Dual service principals**: Use `bedrock.amazonaws.com` for Bedrock Agents resources and `bedrock-agentcore.amazonaws.com` for AgentCore resources
4. **KMS encryption**: Enable customer-managed KMS keys on agent, guardrail, data source, memory, gateway, and token vault resources
5. **Network isolation**: Use VPC network mode for AgentCore runtimes, browsers, and code interpreters in production; restrict OpenSearch Serverless to VPC endpoints
6. **Guardrails**: Always attach guardrails to agents -- enable PROMPT_ATTACK filter, configure PII anonymization, and set topic denials
7. **Secret management**: Use write-only arguments (`api_key_wo`, `client_secret_wo`) for credential providers in Terraform 1.11+
8. **Invocation logging**: Enable model invocation logging to CloudWatch and/or S3 for audit trails
9. **Session TTL**: Set appropriate `idle_session_ttl_in_seconds` to limit data retention exposure
10. **Gateway authorization**: Prefer `CUSTOM_JWT` with scoped audiences and clients, or `AWS_IAM` for service-to-service calls

---

### Alternatives Considered

| Alternative | Why Not |
|---|---|
| API Gateway v2 + Lambda proxy for agent access | AgentCore Gateway provides native MCP support, built-in JWT/IAM auth, and Lambda interceptors -- more integrated and less custom code |
| AWS-managed KMS keys only | Customer-managed keys provide key rotation control, cross-account access, and compliance audit trails |
| OpenSearch Managed Cluster for vector store | OpenSearch Serverless eliminates cluster management, auto-scales, and integrates natively with Bedrock Knowledge Base |
| Single global agent execution role | Per-agent roles with specific model/KB/Lambda scoping follow least-privilege principle |
| Guardrail DRAFT version in production | Immutable guardrail versions (`aws_bedrock_guardrail_version`) ensure production stability during guardrail updates |
| Bedrock Agents only (no AgentCore) | AgentCore adds containerized runtime, MCP gateway, persistent memory, browser, and code interpreter -- required for custom agent code and external tool integration |
| S3 Vectors for knowledge base | Newer option but OpenSearch Serverless is the most mature and widely documented vector store for Bedrock KB |

---

### Sources

- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_agent` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_agent_action_group` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_agent_alias` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_agent_knowledge_base_association` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_knowledge_base` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagent_data_source` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrock_guardrail` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrock_guardrail_version` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrock_model_invocation_logging_configuration` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_agent_runtime` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_agent_runtime_endpoint` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_gateway` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_gateway_target` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_memory` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_memory_strategy` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_browser` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_code_interpreter` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_workload_identity` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_api_key_credential_provider` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_oauth2_credential_provider` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_bedrockagentcore_token_vault_cmk` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_opensearchserverless_collection` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_opensearchserverless_security_policy` resource documentation
- Terraform AWS Provider v6.38.0 -- `aws_opensearchserverless_access_policy` resource documentation
- Public registry module: CloudPediaAI/ai-agent/aws (v1.0.2) -- design pattern reference
- AWS Bedrock Agents documentation: https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html
- AWS Bedrock Knowledge Base documentation: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html
- AWS Bedrock Guardrails documentation: https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html
- AWS Bedrock AgentCore documentation: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/
