## Research: Terraform Registry Module Patterns for Bedrock AgentCore

### Decision

Study existing public registry modules (aws-ia/bedrock, LuisOsuna117/agentcore, Flaconi/bedrock-agent, CloudPediaAI/ai-agent, kogunlowo123/bedrock-platform, Robyt96/bedrock-kb-aurora) and provider resource documentation to identify interface conventions, variable patterns, conditional creation approaches, and "bring your own" resource patterns that should inform the design of the new AgentCore module.

---

### 1. Public Registry Modules Analyzed

#### 1.1 aws-ia/bedrock (70,243 downloads -- most popular)

**Source**: `aws-ia/bedrock/aws` v0.0.33

- **Architecture**: Monolithic module covering agents, knowledge bases, guardrails, data sources, flows, and prompts via submodules
- **Variable patterns**: Uses flat variables (not nested objects) for most configuration; complex configs like `vector_ingestion_configuration` use deeply nested `object()` types with liberal `optional()` usage
- **Conditional creation**: Booleans like `create_opensearch_managed_config` toggle resource blocks
- **Provider version**: `hashicorp/aws` (version not pinned tightly in root)
- **Submodule composition**: Contains dedicated submodules for agents, knowledge bases, guardrails, etc. -- each can be used independently
- **Tag handling**: Standard `tags` map(string)
- **Key outputs**: Returns full resource objects (`agent`, `knowledge_base`, `agent_alias`, etc.) rather than individual attributes -- lets consumers extract what they need

**Lessons**: The monolithic approach with submodules provides flexibility. Flat variables at the root with submodule composition is the most consumer-friendly pattern for complex services.

#### 1.2 LuisOsuna117/agentcore (17 downloads -- most relevant to AgentCore)

**Source**: `LuisOsuna117/agentcore/aws` v0.4.3

- **Architecture**: Composable module with feature flags (`create_runtime`, `create_build_pipeline`, `create_gateway`, `create_memory`)
- **Variable patterns**:
  - Boolean toggles: `create_runtime`, `create_build_pipeline`, `create_gateway`, `create_memory`, `create_execution_role`
  - "Bring your own" pattern: `execution_role_arn` (used when `create_execution_role = false`), `image_uri` (used when `create_build_pipeline = false`), `gateway_role_arn` (used when `gateway_create_role = false`)
  - Name overrides: `runtime_name`, `gateway_name`, `memory_name` all default to `var.name` when null
  - KMS encryption optional: `gateway_kms_key_arn`, `memory_encryption_key_arn` -- null means AWS-managed encryption
  - Additional IAM: `additional_iam_statements` as `list(any)` for appending custom policy statements
  - Environment injection: `environment_variables` as `map(string)`
- **Provider version**: `>= 6.21` (uses newer AgentCore resources)
- **Conditional outputs**: All outputs are `null` when the corresponding `create_*` flag is false
- **Submodules**: `modules/gateway`, `modules/memory` for composable pieces
- **Build pipeline**: Full CodeBuild + ECR + S3 pipeline with `trigger_build_on_apply` toggle
- **Examples**: `basic`, `byo-image`, `codebuild-no-trigger` -- demonstrating different consumption patterns

**Key patterns to adopt**:
- Feature flag booleans for optional components
- "Bring your own" via ARN input + corresponding `create_*` = false
- Null defaults on optional ARN inputs
- Conditional null outputs
- `name` as base prefix with optional per-component name overrides

#### 1.3 Flaconi/bedrock-agent (14 downloads)

**Source**: `Flaconi/bedrock-agent/aws` v1.2.1

- **Architecture**: Tightly coupled agent + knowledge base + OpenSearch module
- **Variable patterns**: Extensive prompt configuration exposed as individual variables (30+ variables for prompt templates, temperatures, top_k, etc.)
- **Complex nested types**: `vector_ingestion_configuration` uses deeply nested objects with `optional()` for chunking strategies; `guardrail_config` is a single complex object with optional sub-blocks
- **Bring your own guardrail**: `guardrail_id` + `guardrail_version` for existing guardrails, OR `guardrail_config` object to create one -- mutually exclusive pattern
- **Additional IAM**: `additional_agent_policy_statements` and `additional_knowledgebase_policy_statements` as `list(object)` with typed structure including optional conditions
- **Provider deps**: aws ~> 6.0, opensearch-project/opensearch ~> 2.3, hashicorp/time ~> 0.13
- **Outputs**: Returns full resource objects (`agent`, `knowledge_base`, `oss_collection`, `agent_alias`)

**Lessons**: Over-exposing prompt configuration as top-level variables creates a sprawling interface. Better to accept a single object or use submodules. The guardrail bring-your-own pattern (ID vs config object) is elegant.

#### 1.4 CloudPediaAI/ai-agent (811 downloads)

**Source**: `CloudPediaAI/ai-agent/aws` v1.0.2

- **Architecture**: Minimal agent module focused on simplicity
- **Variable patterns**: Small interface -- `agent_name`, `foundation_model`, `agent_instruction`, `functions`, `lambda_arn`, `knowledge_base_ids`, `kms_key_arn`, `bucket_name`
- **Functions as map**: `functions = map(object({ parameters = list(string) }))` -- simplified function definition
- **BYO knowledge bases**: Accepts `knowledge_base_ids` list(string) for pre-existing KBs
- **Provider deps**: Uses BOTH `hashicorp/aws ~> 5.94.1` AND `hashicorp/awscc ~> 1.36.0`
- **Outputs**: Only `agent_arn` and `iam_role_arn`

**Lessons**: Minimal interface is good for adoption but limits flexibility. Using both aws and awscc providers is unusual and should be avoided in favor of just the aws provider. Pre-existing knowledge base IDs as a simple list is a clean BYO pattern.

#### 1.5 kogunlowo123/bedrock-platform (3 downloads)

**Source**: `kogunlowo123/bedrock-platform/aws` v1.0.0

- **Architecture**: Platform module creating multiple agents, knowledge bases, and guardrails
- **Variable patterns**: Uses `map(object(...))` for multi-instance resources:
  - `agents = map(object({...}))` with inline action_groups as `list(object({...}))`
  - `knowledge_bases = map(object({...}))`
  - `guardrails = map(object({...}))` with nested filter configs
- **for_each pattern**: Creates multiple resources using map keys, returning `map` outputs (`agent_ids`, `agent_arns`, `knowledge_base_ids`, etc.)
- **Sensible defaults**: `idle_session_ttl = optional(number, 600)`, `chunking_strategy = optional(string, "FIXED_SIZE")`

**Lessons**: `map(object())` with `for_each` is the correct pattern for modules that need to create multiple instances of a resource type. Optional fields with defaults in the object type reduce boilerplate for consumers.

#### 1.6 Robyt96/bedrock-kb-aurora (535 downloads)

**Source**: `Robyt96/bedrock-kb-aurora/aws` v1.1.0

- **Architecture**: Focused knowledge base module with Aurora Serverless vector store
- **Variable patterns**: Clean separation -- `kb_config` as list of KB definitions, `rds_config` for Aurora, `embedding_config` with defaults
- **Multi-KB support**: `list(object({...}))` for creating multiple knowledge bases sharing one Aurora cluster
- **Embedding defaults**: Provides sensible defaults for embedding model and dimensions

**Lessons**: Focused modules that do one thing well are easier to maintain and compose. The list-of-objects pattern for multiple instances is simpler than map-of-objects when key naming is unimportant.

#### 1.7 aws-ia/sagemaker-endpoint (2,116 downloads -- AI/ML reference)

**Source**: `aws-ia/sagemaker-endpoint/aws` v0.0.1

- **Architecture**: SageMaker endpoint with model + endpoint config + IAM
- **Variable patterns**:
  - `containers` as `list(object({...}))` with extensive optional fields
  - `production_variant` as single object with sensible defaults
  - `autoscaling_config` as optional object (null = no autoscaling)
  - `kms_key_arn` optional for encryption at rest
  - `sg_role_arn` for BYO IAM role (null = module creates one)
- **Tag pattern**: `tags = map(string)` with `null` default

**Lessons**: Null-means-disabled pattern for optional feature objects (autoscaling, KMS). The containers list with mixed required/optional fields demonstrates handling complex nested configurations in AI/ML modules.

---

### 2. Provider Resource Landscape (AWS Provider v6.38.0)

#### 2.1 Bedrock Agents Resources (bedrockagent_*)

| Resource | Purpose | Key Arguments |
|----------|---------|---------------|
| `aws_bedrockagent_agent` | Core agent | `agent_name`, `agent_resource_role_arn`, `foundation_model`, `instruction`, `customer_encryption_key_arn`, `guardrail_configuration`, `memory_configuration`, `prompt_override_configuration` |
| `aws_bedrockagent_agent_action_group` | Action groups | `action_group_name`, `agent_id`, `agent_version`, `action_group_executor` (lambda or RETURN_CONTROL), `api_schema` or `function_schema` |
| `aws_bedrockagent_agent_alias` | Version alias | `agent_alias_name`, `agent_id`, `routing_configuration` |
| `aws_bedrockagent_agent_collaborator` | Multi-agent | `agent_id` (supervisor linking) |
| `aws_bedrockagent_agent_knowledge_base_association` | KB linking | `agent_id`, `knowledge_base_id`, `knowledge_base_state`, `description` |
| `aws_bedrockagent_knowledge_base` | Knowledge base | `name`, `role_arn`, `knowledge_base_configuration` (VECTOR/KENDRA/SQL), `storage_configuration` (8 storage types) |
| `aws_bedrockagent_data_source` | Data source for KB | `name`, `knowledge_base_id`, S3/web/etc. source config |
| `aws_bedrockagent_flow` | Agent flows | Flow definition |
| `aws_bedrockagent_prompt` | Prompt templates | Prompt definition |
| `aws_bedrock_guardrail` | Content safety | `name`, `blocked_input_messaging`, `blocked_outputs_messaging`, content/topic/word/sensitive policies |
| `aws_bedrock_guardrail_version` | Guardrail version | `guardrail_id` |

#### 2.2 Bedrock AgentCore Resources (bedrockagentcore_*)

| Resource | Purpose | Key Arguments |
|----------|---------|---------------|
| `aws_bedrockagentcore_agent_runtime` | Container runtime | `agent_runtime_name`, `role_arn`, `agent_runtime_artifact` (container or code), `network_configuration`, `authorizer_configuration`, `protocol_configuration`, `environment_variables` |
| `aws_bedrockagentcore_agent_runtime_endpoint` | Runtime endpoint | `name`, `agent_runtime_id`, `agent_runtime_version` |
| `aws_bedrockagentcore_gateway` | MCP gateway | `name`, `role_arn`, `authorizer_type`, `protocol_type`, `authorizer_configuration`, `interceptor_configuration`, `kms_key_arn` |
| `aws_bedrockagentcore_gateway_target` | Gateway targets | `name`, `gateway_identifier`, `target_configuration` (lambda/API GW/MCP server/OpenAPI/Smithy), `credential_provider_configuration`, `metadata_configuration` |
| `aws_bedrockagentcore_memory` | Persistent memory | `name`, `event_expiry_duration` (7-365 days), `encryption_key_arn`, `memory_execution_role_arn` |
| `aws_bedrockagentcore_memory_strategy` | Memory strategies | `name`, `memory_id`, `type` (SEMANTIC/SUMMARIZATION/USER_PREFERENCE/CUSTOM), `namespaces`, `configuration` (custom overrides) |
| `aws_bedrockagentcore_browser` | Web browsing | `name`, `network_configuration`, `execution_role_arn`, `recording` |
| `aws_bedrockagentcore_code_interpreter` | Code execution | `name`, `network_configuration`, `execution_role_arn` |
| `aws_bedrockagentcore_workload_identity` | OAuth identity | `name`, `allowed_resource_oauth2_return_urls` |
| `aws_bedrockagentcore_api_key_credential_provider` | API key creds | API key credential management |
| `aws_bedrockagentcore_oauth2_credential_provider` | OAuth creds | OAuth credential management |
| `aws_bedrockagentcore_token_vault_cmk` | Token vault CMK | Customer managed key for token vault |

---

### 3. Action Group Definition Patterns

Existing modules handle complex nested action group definitions in several ways:

#### Pattern A: Inline list of objects (kogunlowo123/bedrock-platform)
```hcl
agents = {
  my_agent = {
    name = "agent-1"
    action_groups = [
      {
        name                = "ag1"
        description         = "desc"
        api_schema_payload  = optional(string)
        lambda_function_arn = optional(string)
      }
    ]
  }
}
```
Pros: Single variable for the entire agent config. Cons: Deeply nested, hard to validate individual fields.

#### Pattern B: Separate resources (CloudPediaAI/ai-agent)
```hcl
# Simple function definitions in the variable
functions = {
  "get_claim" = { parameters = ["claim_id"] }
}
lambda_arn = "arn:aws:lambda:..."
```
Pros: Simple interface. Cons: Only supports one Lambda per agent, no API schema support.

#### Pattern C: Provider native (aws_bedrockagent_agent_action_group)
The provider supports two schema approaches:
1. `api_schema` -- OpenAPI schema as inline payload or S3 reference
2. `function_schema` -- Simplified function definitions with typed parameters using `member_functions` / `functions` / `parameters` blocks

**Recommended approach**: Accept action groups as a `list(object)` or `map(object)` where each object specifies the executor type (lambda ARN or RETURN_CONTROL), schema type (api_schema payload, api_schema S3, or function_schema), and the schema content. Use dynamic blocks internally.

---

### 4. Knowledge Base Module Patterns

#### Vector Store Dependency Handling

Existing modules handle the vector store dependency in three ways:

1. **Create everything** (Flaconi/bedrock-agent): Module creates OpenSearch Serverless collection, index, and knowledge base together. Tightly coupled but simple.

2. **BYO vector store** (aws_bedrockagent_knowledge_base provider resource): The provider resource accepts ARNs/endpoints for any of 8 storage backends (OpenSearch Serverless, OpenSearch Managed, Pinecone, RDS, MongoDB, Redis, S3 Vectors, Neptune Analytics). This is the most flexible approach.

3. **Hybrid** (Robyt96/bedrock-kb-aurora): Module creates the Aurora cluster but accepts VPC config. Focused on one storage backend.

**Recommended approach**: Accept pre-existing vector store configuration (collection ARN, index name, field mappings) as input variables. Do NOT create the vector store -- it is a separate concern with its own lifecycle. The knowledge base resource's `storage_configuration` block with 8 backend types makes it impractical to wrap all of them. Instead, accept the storage_configuration as a pass-through object or focus on the most common backend (OpenSearch Serverless) with BYO collection ARN.

---

### 5. Gateway and API Integration Patterns

The `aws_bedrockagentcore_gateway` resource natively supports:
- **Protocol**: Currently only `MCP` (Model Context Protocol)
- **Authorization**: `CUSTOM_JWT` or `AWS_IAM`
- **Targets**: Lambda, API Gateway, MCP Server, OpenAPI Schema, Smithy Model -- via `aws_bedrockagentcore_gateway_target`
- **Interceptors**: Lambda-based request/response interception

The LuisOsuna117/agentcore module uses a boolean `create_gateway` with supporting variables (`gateway_name`, `gateway_description`, `gateway_kms_key_arn`, `gateway_authorizer_type`, `gateway_authorizer_configuration`, `gateway_protocol_type`, `gateway_protocol_configuration`, `gateway_interceptor_configurations`).

**Recommended approach**: Use `create_gateway = false` by default. When enabled, accept the authorizer configuration and protocol configuration as typed objects. Gateway targets should be managed separately (possibly as a list/map variable or separate resources) since they have complex nested schemas and independent lifecycles.

---

### 6. Common Terraform Patterns to Apply

#### 6.1 Conditional Resource Creation

All studied modules use this pattern:
```hcl
variable "create_gateway" {
  type    = bool
  default = false
}

resource "aws_bedrockagentcore_gateway" "this" {
  count = var.create_gateway ? 1 : 0
  ...
}

output "gateway_id" {
  value = try(aws_bedrockagentcore_gateway.this[0].gateway_id, null)
}
```

For multi-instance resources, `for_each` on a map:
```hcl
variable "memory_strategies" {
  type = map(object({...}))
  default = {}
}

resource "aws_bedrockagentcore_memory_strategy" "this" {
  for_each = var.memory_strategies
  name     = each.value.name
  ...
}
```

#### 6.2 Dynamic Blocks for Nested Configuration

Used by Flaconi and aws-ia modules for prompt overrides, guardrail configs:
```hcl
dynamic "guardrail_configuration" {
  for_each = var.guardrail_id != null ? [1] : []
  content {
    guardrail_identifier = var.guardrail_id
    guardrail_version    = var.guardrail_version
  }
}
```

#### 6.3 Variable Validation Blocks

```hcl
variable "event_expiry_duration" {
  type = number
  validation {
    condition     = var.event_expiry_duration >= 7 && var.event_expiry_duration <= 365
    error_message = "event_expiry_duration must be between 7 and 365 days."
  }
}

variable "network_mode" {
  type = string
  validation {
    condition     = contains(["PUBLIC", "VPC"], var.network_mode)
    error_message = "network_mode must be PUBLIC or VPC."
  }
}
```

#### 6.4 Conditional Output Values

Pattern from LuisOsuna117/agentcore:
```hcl
output "gateway_id" {
  description = "Unique identifier of the AgentCore Gateway. Null when create_gateway = false."
  value       = var.create_gateway ? aws_bedrockagentcore_gateway.this[0].gateway_id : null
}
```

---

### 7. Module Composition / "Bring Your Own" Patterns

Three patterns observed across studied modules:

#### Pattern A: Boolean Toggle + ARN Input (LuisOsuna117/agentcore)
```hcl
variable "create_execution_role" {
  type    = bool
  default = true
}
variable "execution_role_arn" {
  type    = string
  default = null
}
# Internal: local.execution_role_arn = var.create_execution_role ? aws_iam_role.this[0].arn : var.execution_role_arn
```

#### Pattern B: Null-means-create (SageMaker endpoint)
```hcl
variable "kms_key_arn" {
  type    = string
  default = null  # null = AWS-managed encryption, string = BYO KMS key
}
```

#### Pattern C: Object-or-ID (Flaconi/bedrock-agent)
```hcl
variable "guardrail_id" {
  type    = string
  default = null  # Provide existing guardrail ID...
}
variable "guardrail_config" {
  type    = object({...})
  default = null  # ...OR provide config to create one
}
```

**Recommended approach for the AgentCore module**: Use Pattern A (boolean + ARN) for IAM roles and KMS keys. Use Pattern B (null-means-default) for encryption. Use Pattern A for optional components like gateway, memory, browser, and code interpreter.

---

### 8. Architectural Recommendations for AgentCore Module

Based on the registry analysis:

1. **Composable feature flags**: Follow LuisOsuna117/agentcore pattern with `create_runtime`, `create_gateway`, `create_memory`, `create_browser`, `create_code_interpreter` booleans

2. **BYO resources**: Support `execution_role_arn`, `kms_key_arn`, `image_uri` as BYO inputs with corresponding `create_*` flags

3. **Single `name` prefix**: Use one `name` variable as prefix for all resources, with optional per-component name overrides

4. **Typed object variables**: For complex configs (authorizer, protocol, network), use typed `object()` variables with `optional()` fields and sensible defaults

5. **Map outputs**: Return individual attributes (ID, ARN, name) not full resource objects -- cleaner for consumers and avoids exposing internal structure

6. **Provider version**: Require `>= 6.21` for AgentCore resource support (based on LuisOsuna117 precedent and the bedrockagentcore_* resources in provider v6.38.0)

7. **Avoid over-exposure**: Do NOT expose every prompt template, temperature, and token parameter as top-level variables (Flaconi anti-pattern). Group related configs into objects or use pass-through variables.

8. **Memory strategies as map**: Accept `memory_strategies` as `map(object({...}))` for flexible strategy definition using `for_each`

9. **Gateway targets separate**: Keep gateway target definitions in a separate variable or submodule due to their complexity (Lambda targets with inline tool schemas, API Gateway targets, MCP server targets)

10. **Tags propagation**: Standard `tags = map(string)` with `{}` default, applied to all taggable resources

---

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Monolithic module like aws-ia/bedrock | Too large scope for AgentCore which already has many resource types; composable flags are more flexible |
| Using awscc provider (CloudPediaAI pattern) | Adds unnecessary provider dependency; aws provider v6.x has full AgentCore support |
| Creating vector store in the module (Flaconi pattern) | Vector stores have independent lifecycle and 8 backend options; impractical to wrap all |
| Flat variables for all config (Flaconi prompt pattern) | Creates 30+ top-level variables; grouped objects are more maintainable |
| list(object) for multi-instance (Robyt96 pattern) | map(object) with for_each provides stable resource addresses and is preferred for Terraform |
| Creating build pipeline in module (LuisOsuna117 pattern) | CodeBuild + ECR + S3 adds significant complexity; should be a separate module or CI/CD concern |

### Sources

- Terraform Registry: `aws-ia/bedrock/aws` v0.0.33 (70,243 downloads)
- Terraform Registry: `LuisOsuna117/agentcore/aws` v0.4.3 (17 downloads, most relevant AgentCore module)
- Terraform Registry: `Flaconi/bedrock-agent/aws` v1.2.1 (14 downloads)
- Terraform Registry: `CloudPediaAI/ai-agent/aws` v1.0.2 (811 downloads)
- Terraform Registry: `kogunlowo123/bedrock-platform/aws` v1.0.0 (3 downloads)
- Terraform Registry: `Robyt96/bedrock-kb-aurora/aws` v1.1.0 (535 downloads)
- Terraform Registry: `aws-ia/sagemaker-endpoint/aws` v0.0.1 (2,116 downloads)
- AWS Provider v6.38.0: `aws_bedrockagent_agent`, `aws_bedrockagent_agent_action_group`, `aws_bedrockagent_agent_alias`, `aws_bedrockagent_agent_knowledge_base_association`, `aws_bedrockagent_knowledge_base`, `aws_bedrockagent_data_source`
- AWS Provider v6.38.0: `aws_bedrockagentcore_agent_runtime`, `aws_bedrockagentcore_agent_runtime_endpoint`, `aws_bedrockagentcore_gateway`, `aws_bedrockagentcore_gateway_target`, `aws_bedrockagentcore_memory`, `aws_bedrockagentcore_memory_strategy`, `aws_bedrockagentcore_browser`, `aws_bedrockagentcore_code_interpreter`, `aws_bedrockagentcore_workload_identity`
- AWS Provider v6.38.0: `aws_bedrock_guardrail`, `aws_bedrock_guardrail_version`
