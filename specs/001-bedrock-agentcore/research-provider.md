## Research: AWS Terraform Provider Resources for Bedrock Agents

### Decision

Use the `aws_bedrockagent_*` resource family (agent, agent_alias, agent_action_group, knowledge_base, agent_knowledge_base_association, data_source) plus `aws_bedrock_guardrail` and `aws_bedrock_guardrail_version` from the hashicorp/aws provider >= 6.0. These resources are stable and well-documented in provider version 6.38.0 (latest as of this research). The newer `aws_bedrockagentcore_*` resources exist for AgentCore Runtime (containerized agent execution) but are a separate service and not needed for standard Bedrock Agents.

---

### Resources Identified

#### 1. `aws_bedrockagent_agent` -- The Agent itself

**Purpose**: Creates and manages an Amazon Bedrock Agent, which orchestrates foundation model invocations, action groups, and knowledge bases.

**Required Arguments**:
- `agent_name` (string) -- Name of the agent
- `agent_resource_role_arn` (string) -- ARN of IAM role with `bedrock:InvokeModel` permissions. Must trust `bedrock.amazonaws.com` with `sts:AssumeRole`, scoped by `aws:SourceAccount` and `AWS:SourceArn` conditions
- `foundation_model` (string) -- Model ID, e.g. `"anthropic.claude-v2"`, `"anthropic.claude-3-5-sonnet-20241022-v2:0"`

**Optional Arguments**:
- `instruction` (string, 40-20000 chars) -- Agent behavior instructions. **Required if `prepare_agent = true`** (the default)
- `idle_session_ttl_in_seconds` (number) -- Session timeout. Default is AWS service default (not set by provider)
- `customer_encryption_key_arn` (string) -- KMS key ARN for encryption at rest
- `prepare_agent` (bool, default `true`) -- **Critical**: When true, the provider automatically prepares/builds the agent after create/update. When false, agent stays in DRAFT and must be prepared separately or via alias creation
- `description` (string)
- `guardrail_configuration` (block) -- Associates a guardrail: `guardrail_identifier` + `guardrail_version`
- `memory_configuration` (block) -- Enables conversation memory: `enabled_memory_types` (e.g. `["SESSION_SUMMARY"]`), `storage_days` (0-30), `session_summary_configuration.max_recent_sessions`
- `prompt_override_configuration` (block) -- Override default prompt templates for agent pipeline steps. Contains:
  - `prompt_configurations` (list of blocks, required within this block) -- Each block requires: `base_prompt_template`, `inference_configuration`, `parser_mode`, `prompt_creation_mode`, `prompt_state`, `prompt_type`
  - `override_lambda` (string, optional) -- Lambda ARN for custom parser. Required if any `prompt_configurations` has `parser_mode = "OVERRIDDEN"`
  - Valid `prompt_type` values: `PRE_PROCESSING`, `ORCHESTRATION`, `POST_PROCESSING`, `KNOWLEDGE_BASE_RESPONSE_GENERATION`
  - `inference_configuration` requires ALL of: `max_length`, `stop_sequences`, `temperature`, `top_k`, `top_p`
- `agent_collaboration` (string) -- For multi-agent collaboration: `SUPERVISOR`, `SUPERVISOR_ROUTER`, or `DISABLED`
- `skip_resource_in_use_check` (bool) -- Skip in-use check on delete
- `tags` (map)

**Computed Attributes (Outputs)**:
- `agent_arn` (string) -- Full ARN of the agent
- `agent_id` (string) -- Unique agent identifier (10-char alphanumeric)
- `agent_version` (string) -- Current version
- `id` (string) -- Same as `agent_id`
- `prepared_at` (string) -- Timestamp of last preparation

**Timeouts**: create/update/delete all 5m

**Import**: By agent ID, e.g. `GGRRAED6JP`

---

#### 2. `aws_bedrockagent_agent_alias` -- Agent Alias (for versioning/routing)

**Purpose**: Creates an alias that points to a specific agent version. Required for invoking the agent via the runtime API. Creating an alias on a prepared agent snapshots the DRAFT into a numbered version.

**Required Arguments**:
- `agent_alias_name` (string) -- Name of the alias
- `agent_id` (string, ForceNew) -- Agent to create alias for

**Optional Arguments**:
- `description` (string)
- `routing_configuration` (block) -- Controls which version the alias routes to:
  - `agent_version` (string) -- Version number to route to. If omitted, the alias automatically points to the latest prepared version
  - `provisioned_throughput` (string) -- ARN of Provisioned Throughput for the alias
- `tags` (map)

**Computed Attributes**:
- `agent_alias_arn` (string) -- Full ARN of the alias
- `agent_alias_id` (string) -- Unique alias identifier
- `id` (string) -- Composite: `{alias_id},{agent_id}`

**Versioning Behavior**:
- When alias is created without `routing_configuration`, it pins to the latest version at creation time
- Updating the alias (e.g. changing description) can trigger re-preparation and version bump
- Explicit `routing_configuration.agent_version` pins to a specific version

**Timeouts**: create/update/delete all 5m

**Import**: By `{alias_id},{agent_id}`, e.g. `66IVY0GUTF,GGRRAED6JP`

---

#### 3. `aws_bedrockagent_agent_action_group` -- Action Group (Lambda/API binding)

**Purpose**: Attaches an action group to an agent, enabling the agent to invoke Lambda functions or return control to the caller. Action groups define the APIs/functions the agent can call.

**Required Arguments**:
- `action_group_name` (string)
- `agent_id` (string) -- Agent to attach to
- `agent_version` (string) -- **Must be `"DRAFT"`** -- action groups can only be attached to the draft version
- `action_group_executor` (block) -- How the action is executed:
  - `lambda` (string) -- Lambda function ARN. Mutually exclusive with `custom_control`
  - `custom_control` (string) -- `"RETURN_CONTROL"` for returning predicted actions to caller. Mutually exclusive with `lambda`

**Optional Arguments**:
- `api_schema` (block) -- OpenAPI schema defining the action group's API:
  - `payload` (string) -- Inline JSON/YAML OpenAPI schema. Mutually exclusive with `s3`
  - `s3` (block) -- S3-hosted schema: `s3_bucket_name` + `s3_object_key`. Mutually exclusive with `payload`
- `function_schema` (block) -- Simplified alternative to `api_schema` for defining functions directly:
  - `member_functions.functions` (list) -- Each function has: `name` (required), `description`, and `parameters` blocks
  - `parameters`: `map_block_key` (parameter name -- **note the unusual argument name for backward compatibility**), `type` (string/number/integer/boolean/array), `description`, `required`
- `parent_action_group_signature` (string) -- For built-in action groups:
  - `"AMAZON.UserInput"` -- Enables the agent to request additional info from users. When using this, leave `description`, `api_schema`, and `action_group_executor` blank
  - `"AMAZON.CodeInterpreter"` -- Enables code interpreter capability (see details below)
- `action_group_state` (string) -- `ENABLED` or `DISABLED`
- `description` (string)
- `prepare_agent` (bool, default `true`) -- Whether to re-prepare agent after this change
- `skip_resource_in_use_check` (bool)

**Computed Attributes**:
- `action_group_id` (string)
- `id` (string) -- Composite: `{action_group_id},{agent_id},{agent_version}`

**Code Interpreter Action Group**:
The provider docs for `parent_action_group_signature` only list `AMAZON.UserInput` as a valid value. However, the AWS API supports `AMAZON.CodeInterpreter` as well. To use it:
```hcl
resource "aws_bedrockagent_agent_action_group" "code_interpreter" {
  action_group_name          = "CodeInterpreter"
  agent_id                   = aws_bedrockagent_agent.example.agent_id
  agent_version              = "DRAFT"
  parent_action_group_signature = "AMAZON.CodeInterpreter"
  skip_resource_in_use_check = true
}
```
When using `parent_action_group_signature`, the `action_group_executor`, `api_schema`, and `function_schema` arguments should be omitted (the AWS service handles execution internally). This is a **documentation gap** in the provider -- the valid values list is incomplete.

**Schema Choice (api_schema vs function_schema)**:
- `api_schema` -- Use for full OpenAPI spec with HTTP endpoints; supports inline payload or S3-hosted file
- `function_schema` -- Use for simpler function definitions without full OpenAPI; parameters defined directly in Terraform
- Only one of `api_schema` or `function_schema` should be specified (they are mutually exclusive)

**Timeouts**: create/update/delete all 30m (notably longer than agent itself)

**Import**: By `{action_group_id},{agent_id},DRAFT`

---

#### 4. `aws_bedrockagent_knowledge_base` -- Knowledge Base

**Purpose**: Creates a knowledge base backed by a vector store, enabling RAG (Retrieval-Augmented Generation) for agents.

**Required Arguments**:
- `name` (string)
- `role_arn` (string) -- IAM role for the KB. Needs permissions to access the embedding model and the vector store
- `knowledge_base_configuration` (block, ForceNew):
  - `type` (string, required) -- `"VECTOR"`, `"KENDRA"`, or `"SQL"`
  - `vector_knowledge_base_configuration` (block, for VECTOR type):
    - `embedding_model_arn` (string, required) -- e.g. `"arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0"`
    - `embedding_model_configuration` (optional) -- `bedrock_embedding_model_configuration.dimensions` and `embedding_data_type` (FLOAT32/BINARY)
    - `supplemental_data_storage_configuration` (optional) -- S3 location for extracted images from multimodal documents
  - `kendra_knowledge_base_configuration` (block, for KENDRA type):
    - `kendra_index_arn` (required)
  - `sql_knowledge_base_configuration` (block, for SQL type):
    - Redshift configuration with provisioned or serverless query engine

**Optional Arguments**:
- `storage_configuration` (block, ForceNew) -- Vector store backend:
  - `type` (required) -- Valid values: `OPENSEARCH_SERVERLESS`, `OPENSEARCH_MANAGED_CLUSTER`, `PINECONE`, `RDS`, `REDIS_ENTERPRISE_CLOUD`, `MONGO_DB_ATLAS`, `NEPTUNE_ANALYTICS`, `S3_VECTORS`
  - Each type has a corresponding configuration block with `field_mapping` (vector_field, text_field, metadata_field)
  - **OpenSearch Serverless** (most common): `collection_arn`, `vector_index_name`, `field_mapping`
  - **RDS (PostgreSQL with pgvector)**: `resource_arn`, `credentials_secret_arn`, `database_name`, `table_name`, `field_mapping` (includes `primary_key_field`, `custom_metadata_field`)
  - **Pinecone**: `connection_string`, `credentials_secret_arn`, `field_mapping`, `namespace`
  - **S3 Vectors** (newest): `index_arn` or `index_name` + `vector_bucket_arn`
- `description` (string)
- `tags` (map)

**Computed Attributes**:
- `arn` (string) -- KB ARN
- `id` (string) -- KB ID (10-char alphanumeric)
- `created_at` (string)
- `updated_at` (string)

**Important Notes**:
- Both `knowledge_base_configuration` and `storage_configuration` are **ForceNew** -- changing them destroys and recreates the KB
- The `storage_configuration` is Optional in the schema, but required for VECTOR type KBs (KENDRA and SQL types don't need it)
- The role must have permissions for both the embedding model (`bedrock:InvokeModel`) and the vector store

**Timeouts**: create/update/delete all 30m

**Import**: By knowledge base ID

---

#### 5. `aws_bedrockagent_agent_knowledge_base_association` -- KB-to-Agent binding

**Purpose**: Associates an existing knowledge base with an agent, enabling the agent to query the KB during conversations.

**Required Arguments**:
- `agent_id` (string, ForceNew) -- Agent to associate with
- `description` (string, required) -- Description of what the agent should use the KB for. **This is used by the agent's orchestration to decide when to query the KB** -- it is semantically meaningful, not just documentation
- `knowledge_base_id` (string, ForceNew) -- KB to associate
- `knowledge_base_state` (string) -- `"ENABLED"` or `"DISABLED"`

**Optional Arguments**:
- `agent_version` (string, ForceNew) -- Must be `"DRAFT"` if specified

**Computed Attributes**:
- `id` (string) -- Composite: `{agent_id},{agent_version},{knowledge_base_id}`

**Timeouts**: create/update/delete all 5m

**Import**: By `{agent_id},DRAFT,{knowledge_base_id}`

---

#### 6. `aws_bedrockagent_data_source` -- Data Source for Knowledge Base

**Purpose**: Configures a data source (S3, Web, Confluence, Salesforce, SharePoint, Custom, Redshift) that feeds documents into a knowledge base for vector ingestion.

**Required Arguments**:
- `knowledge_base_id` (string) -- KB to attach to
- `name` (string, ForceNew)
- `data_source_configuration` (block):
  - `type` (string, required) -- `"S3"`, `"WEB"`, `"CONFLUENCE"`, `"SALESFORCE"`, `"SHAREPOINT"`, `"CUSTOM"`, `"REDSHIFT_METADATA"`
  - `s3_configuration` (for S3 type):
    - `bucket_arn` (required)
    - `bucket_owner_account_id` (optional)
    - `inclusion_prefixes` (optional, set of strings) -- S3 key prefixes to include

**Optional Arguments**:
- `data_deletion_policy` (string) -- `"RETAIN"` or `"DELETE"` -- controls what happens to indexed data when the data source is deleted
- `description` (string)
- `server_side_encryption_configuration` (block) -- `kms_key_arn` for encrypting the data source
- `vector_ingestion_configuration` (block, ForceNew) -- Chunking and parsing configuration:
  - `chunking_configuration`:
    - `chunking_strategy` (required) -- `"FIXED_SIZE"`, `"HIERARCHICAL"`, `"SEMANTIC"`, `"NONE"`
    - `fixed_size_chunking_configuration`: `max_tokens`, `overlap_percentage`
    - `hierarchical_chunking_configuration`: two `level_configuration` blocks with `max_tokens`, plus `overlap_tokens`
    - `semantic_chunking_configuration`: `breakpoint_percentile_threshold`, `buffer_size`, `max_token`
  - `parsing_configuration`:
    - `parsing_strategy` -- `"BEDROCK_FOUNDATION_MODEL"` or `"BEDROCK_DATA_AUTOMATION"`
    - `bedrock_foundation_model_configuration`: `model_arn`, `parsing_modality` (MULTIMODAL), `parsing_prompt.parsing_prompt_string`
  - `custom_transformation_configuration` -- Lambda-based post-chunking transformation

**Computed Attributes**:
- `data_source_id` (string)
- `id` (string) -- Composite: `{data_source_id},{knowledge_base_id}`

**Important**: `vector_ingestion_configuration` is ForceNew -- changing chunking or parsing destroys and recreates the data source

**Timeouts**: create 30m, delete 30m (no update timeout documented)

**Import**: By `{data_source_id},{knowledge_base_id}`

---

#### 7. `aws_bedrock_guardrail` -- Guardrail Configuration

**Purpose**: Creates content filtering guardrails that can be attached to agents or used directly with model invocations.

**Required Arguments**:
- `name` (string)
- `blocked_input_messaging` (string) -- Message returned when input is blocked
- `blocked_outputs_messaging` (string) -- Message returned when output is blocked

**Optional Arguments**:
- `description` (string)
- `kms_key_arn` (string) -- KMS key for encryption
- `content_policy_config` (block):
  - `filters_config` -- Content filters for: `SEXUAL`, `VIOLENCE`, `HATE`, `INSULTS`, `MISCONDUCT`, `PROMPT_ATTACK`
  - Each filter has `input_strength`/`output_strength` (NONE/LOW/MEDIUM/HIGH) and granular `input_action`/`output_action` (BLOCK/NONE) plus `input_enabled`/`output_enabled` toggles
  - `tier_config.tier_name` -- `"STANDARD"` or `"CLASSIC"`
  - Supports `input_modalities`/`output_modalities` (IMAGE, TEXT)
- `topic_policy_config` (block):
  - `topics_config` -- Custom topic definitions with `name`, `definition`, `type` (DENY), `examples`
  - `tier_config.tier_name` -- `"STANDARD"` or `"CLASSIC"`
- `sensitive_information_policy_config` (block):
  - `pii_entities_config` -- PII detection: `type` (NAME, EMAIL, PHONE, SSN, etc.), `action` (BLOCK/ANONYMIZE/NONE), granular input/output controls
  - `regexes_config` -- Custom regex patterns: `name`, `pattern`, `action`, `description`
- `word_policy_config` (block):
  - `managed_word_lists_config` -- Built-in word lists: `type = "PROFANITY"`
  - `words_config` -- Custom blocked words: `text`
- `contextual_grounding_policy_config` (block):
  - `filters_config` -- Grounding filters with `threshold` and `type`
- `tags` (map)

**Computed Attributes**:
- `guardrail_arn` (string)
- `guardrail_id` (string)
- `version` (string) -- DRAFT version
- `status` (string) -- `READY` or `FAILED`
- `created_at` (string)

**Timeouts**: create/update/delete all 5m

**Import**: By `{guardrail_id},DRAFT`

---

#### 8. `aws_bedrock_guardrail_version` -- Guardrail Version (immutable snapshot)

**Purpose**: Creates an immutable versioned snapshot of a guardrail. Guardrails are always edited in DRAFT; versions are snapshots for production use.

**Required Arguments**:
- `guardrail_arn` (string) -- ARN of the guardrail to version

**Optional Arguments**:
- `description` (string)
- `skip_destroy` (bool, default `false`) -- When true, retains the version in AWS when the Terraform resource is destroyed. Useful for preserving old versions.

**Computed Attributes**:
- `version` (string) -- Version number (numeric string)

**Timeouts**: create 5m, delete 5m

**Import**: By `{guardrail_arn},{version_number}`

---

### Supporting Resources (not bedrockagent-specific but required)

- **`aws_iam_role`** -- Agent execution role trusting `bedrock.amazonaws.com`; KB role for embedding model and vector store access
- **`aws_iam_role_policy` / `aws_iam_policy`** -- `bedrock:InvokeModel` on foundation model ARNs, S3 access for data sources, OpenSearch/RDS/Pinecone access for vector stores
- **`aws_lambda_function`** + `aws_lambda_permission`** -- For action group executors; Lambda must grant `bedrock.amazonaws.com` invoke permission
- **`aws_s3_bucket`** -- For data source documents and/or API schema hosting
- **`aws_opensearchserverless_collection`** + `aws_opensearchserverless_access_policy` + `aws_opensearchserverless_security_policy`** -- For OpenSearch Serverless vector store backend

---

### Additional Resources Discovered

#### `aws_bedrockagent_agent_collaborator` -- Multi-Agent Collaboration

For supervisor/collaborator patterns. Requires:
- Supervisor agent with `agent_collaboration = "SUPERVISOR"` or `"SUPERVISOR_ROUTER"`
- Collaborator agents with their own aliases
- `aws_bedrockagent_agent_collaborator` resource linking them

#### `aws_bedrockagentcore_*` -- AgentCore Resources (separate service)

A newer set of resources under `Bedrock AgentCore` subcategory (provider 6.38.0):
- `aws_bedrockagentcore_agent_runtime` -- Containerized agent runtime (ECR or S3 code)
- `aws_bedrockagentcore_agent_runtime_endpoint` -- Endpoint for runtime
- `aws_bedrockagentcore_code_interpreter` -- Managed code interpreter environment
- `aws_bedrockagentcore_gateway` / `gateway_target` -- API gateway for agents
- `aws_bedrockagentcore_memory` / `memory_strategy` -- External memory management
- `aws_bedrockagentcore_browser` -- Browser tool for agents
- `aws_bedrockagentcore_workload_identity` -- Workload identity management
- `aws_bedrockagentcore_oauth2_credential_provider` / `api_key_credential_provider` -- Credential providers
- `aws_bedrockagentcore_token_vault_cmk` -- Token vault encryption

These are distinct from the `bedrockagent_*` resources and represent a container-based agent hosting model (supports MCP, A2A protocols). They are NOT required for standard Bedrock Agents.

#### `aws_bedrockagent_agent_versions` -- Data Source

Data source for listing agent versions. Useful for querying available versions programmatically.

---

### Key Arguments Summary Table

| Resource | Key Required Args | Key Optional Args |
|----------|------------------|-------------------|
| `bedrockagent_agent` | `agent_name`, `agent_resource_role_arn`, `foundation_model` | `instruction`, `prepare_agent`, `idle_session_ttl_in_seconds`, `customer_encryption_key_arn`, `guardrail_configuration`, `prompt_override_configuration`, `memory_configuration` |
| `bedrockagent_agent_alias` | `agent_alias_name`, `agent_id` | `routing_configuration`, `description`, `tags` |
| `bedrockagent_agent_action_group` | `action_group_name`, `agent_id`, `agent_version` (DRAFT), `action_group_executor` | `api_schema`, `function_schema`, `parent_action_group_signature`, `prepare_agent` |
| `bedrockagent_knowledge_base` | `name`, `role_arn`, `knowledge_base_configuration` | `storage_configuration`, `description`, `tags` |
| `bedrockagent_agent_knowledge_base_association` | `agent_id`, `knowledge_base_id`, `description`, `knowledge_base_state` | `agent_version` |
| `bedrockagent_data_source` | `knowledge_base_id`, `name`, `data_source_configuration` | `vector_ingestion_configuration`, `data_deletion_policy`, `server_side_encryption_configuration` |
| `bedrock_guardrail` | `name`, `blocked_input_messaging`, `blocked_outputs_messaging` | `content_policy_config`, `topic_policy_config`, `sensitive_information_policy_config`, `word_policy_config`, `kms_key_arn` |
| `bedrock_guardrail_version` | `guardrail_arn` | `description`, `skip_destroy` |

---

### Key Outputs Summary Table

| Resource | Output | Type | Description |
|----------|--------|------|-------------|
| `bedrockagent_agent` | `agent_arn` | string | Full ARN |
| `bedrockagent_agent` | `agent_id` | string | Agent identifier |
| `bedrockagent_agent` | `agent_version` | string | Current version |
| `bedrockagent_agent_alias` | `agent_alias_arn` | string | Alias ARN (used for InvokeAgent) |
| `bedrockagent_agent_alias` | `agent_alias_id` | string | Alias identifier |
| `bedrockagent_agent_action_group` | `action_group_id` | string | Action group identifier |
| `bedrockagent_knowledge_base` | `arn` | string | KB ARN |
| `bedrockagent_knowledge_base` | `id` | string | KB identifier |
| `bedrockagent_data_source` | `data_source_id` | string | Data source identifier |
| `bedrock_guardrail` | `guardrail_arn` | string | Guardrail ARN |
| `bedrock_guardrail` | `guardrail_id` | string | Guardrail identifier |
| `bedrock_guardrail` | `version` | string | DRAFT version string |
| `bedrock_guardrail_version` | `version` | string | Numbered version |

---

### Security Considerations

1. **IAM Role for Agent**: Must follow least-privilege. Trust policy should scope to specific account (`aws:SourceAccount`) and agent ARN pattern (`AWS:SourceArn`). The role needs `bedrock:InvokeModel` on specific foundation model ARNs only.

2. **IAM Role for Knowledge Base**: Separate role from agent. Needs embedding model invocation permissions plus vector store access (OpenSearch/RDS/Pinecone credentials).

3. **KMS Encryption**:
   - Agent: `customer_encryption_key_arn` for agent data encryption
   - Data Source: `server_side_encryption_configuration.kms_key_arn`
   - Guardrail: `kms_key_arn`
   - All three support customer-managed KMS keys

4. **Lambda Permissions**: Action group Lambda functions must have a resource-based policy granting `bedrock.amazonaws.com` the `lambda:InvokeFunction` permission.

5. **Data Deletion Policy**: `data_deletion_policy` on data sources controls whether indexed vectors are retained or deleted when the data source is removed. Default behavior should be explicitly set.

6. **Guardrail Content Filtering**: Enable content filters (HATE, VIOLENCE, SEXUAL, MISCONDUCT, INSULTS, PROMPT_ATTACK) with appropriate strength levels. Use PII entity detection for sensitive data handling.

7. **Network**: Standard Bedrock Agent resources use AWS-managed networking. For VPC-isolated deployments, the newer AgentCore resources (`bedrockagentcore_agent_runtime`) support VPC network mode.

---

### Gotchas and Known Issues

1. **`prepare_agent` timing**: The `prepare_agent = true` default means the agent is automatically prepared after every create/update. If you have action groups or KB associations that are created in the same apply, the agent may be prepared before those are attached. **Workaround**: Set `prepare_agent = false` on the agent and action groups, then either:
   - Create an alias (which triggers preparation), or
   - Use a `null_resource` with a local-exec provisioner to call `aws bedrock-agent prepare-agent`

2. **Action group `agent_version` must be `"DRAFT"`**: Action groups can only be attached to the DRAFT version. This is enforced by the API.

3. **`parent_action_group_signature` documentation gap**: The provider docs only list `AMAZON.UserInput` as a valid value, but `AMAZON.CodeInterpreter` is also supported by the AWS API. When using either signature, omit `action_group_executor`, `api_schema`, and `function_schema`.

4. **`map_block_key` naming**: In `function_schema` parameters, the parameter name field is called `map_block_key` due to a backward compatibility issue in the provider. This is confusing but correct.

5. **Knowledge base `storage_configuration` is ForceNew**: Changing the vector store type or configuration destroys and recreates the entire KB plus all associated data sources.

6. **Data source `vector_ingestion_configuration` is ForceNew**: Changing chunking strategy requires destroying and recreating the data source. Plan chunking strategy carefully before deployment.

7. **Guardrail versioning model**: Guardrails use a DRAFT/version model similar to agents. The `aws_bedrock_guardrail` resource always manages the DRAFT. Use `aws_bedrock_guardrail_version` to create immutable numbered versions for production. The `guardrail_configuration` on the agent references a specific version.

8. **Agent preparation can be slow**: Preparation involves model compilation and validation. The 5-minute timeout is usually sufficient but can be tight for complex agents.

9. **Alias creation triggers versioning**: Creating or updating an alias can snapshot the DRAFT into a new numbered version. This means state may drift if the alias is updated outside Terraform.

10. **Knowledge base association `description` is semantically meaningful**: The `description` field on `aws_bedrockagent_agent_knowledge_base_association` is not just documentation -- the agent's orchestrator uses it to decide when to query the KB. Write clear, specific descriptions.

11. **No built-in data source sync**: The `aws_bedrockagent_data_source` resource creates the data source configuration but does NOT trigger an ingestion sync. You must call `StartIngestionJob` via the AWS API/CLI separately after creating or updating a data source.

---

### Minimum Provider Version

The current provider documentation is from version **6.38.0**. Key resource introduction timeline:
- `aws_bedrockagent_agent`, `aws_bedrockagent_agent_alias`, `aws_bedrockagent_agent_action_group`, `aws_bedrockagent_knowledge_base`, `aws_bedrockagent_data_source`: Available since provider ~5.31+ (late 2023/early 2024)
- `aws_bedrockagent_agent_knowledge_base_association`: Added slightly later
- `aws_bedrock_guardrail` and `aws_bedrock_guardrail_version`: Added in provider ~5.49+
- `aws_bedrockagent_agent_collaborator`: Added in provider ~5.70+
- `aws_bedrockagentcore_*` resources: Added in provider 6.x

**Recommended minimum**: `>= 5.75.0` for all bedrockagent resources including collaborators and guardrails. For the latest features (S3 Vectors storage, Neptune Analytics, OpenSearch Managed Cluster, multimodal parsing), use `>= 6.0`. The Flaconi public module requires `~> 6.0`.

**Safe minimum for comprehensive Bedrock Agent support**: `>= 6.0`

---

### How Agent Preparation Works

1. When `prepare_agent = true` (default), Terraform calls the `PrepareAgent` API after creating or updating the agent
2. Preparation validates the agent configuration, compiles prompt templates, and makes the DRAFT version ready for alias creation
3. The agent must have a valid `instruction` when preparing
4. Preparation transitions the agent from `NOT_PREPARED` to `PREPARED` status
5. Action groups and KB associations added after initial preparation require re-preparation
6. Creating an alias also triggers preparation if the agent is not already prepared
7. The `prepared_at` attribute tracks the last preparation timestamp

---

### How Code Interpreter Works

The Code Interpreter action group allows the agent to generate and execute Python code:

1. Create an action group with `parent_action_group_signature = "AMAZON.CodeInterpreter"`
2. Do NOT specify `action_group_executor`, `api_schema`, or `function_schema` -- AWS manages the execution environment
3. The agent can then write and execute Python code to answer questions involving calculations, data analysis, or file processing
4. Code execution happens in a sandboxed AWS-managed environment
5. This is distinct from the `aws_bedrockagentcore_code_interpreter` resource, which is for the newer AgentCore service

**Note**: The `AMAZON.CodeInterpreter` value for `parent_action_group_signature` is underdocumented in the Terraform provider but is supported by the underlying AWS API. If the provider rejects the value, it may need a provider version update.

---

### Public Registry Module Patterns

The **Flaconi/bedrock-agent/aws** module (v1.2.1, `~> 6.0` provider) demonstrates:
- Full prompt override configuration with all 4 prompt types (pre-processing, orchestration, post-processing, KB response generation)
- OpenSearch Serverless as the default vector store
- Fixed-size chunking with 300 max tokens and 20% overlap as defaults
- Separate IAM roles for agent and knowledge base
- Optional guardrail creation vs. referencing existing guardrail
- S3 data source with configurable inclusion prefixes
- Agent alias as a required output for consumers
- Tags propagation throughout all resources

---

### Rationale

The `aws_bedrockagent_*` resource family provides complete coverage for building Bedrock Agents with knowledge bases, action groups, and guardrails via Terraform. The resources are stable in provider 6.x, well-documented (with the exceptions noted), and follow standard Terraform patterns. The newer `aws_bedrockagentcore_*` resources are for a different use case (containerized agent hosting with MCP/A2A protocol support) and should be treated as a separate concern.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| `aws_bedrockagentcore_agent_runtime` | Different service -- for containerized agent hosting, not standard Bedrock Agents |
| AWS CloudFormation `AWS::Bedrock::Agent` | Not Terraform; different IaC tool |
| `awscc_bedrock_agent` (Cloud Control) | Less mature, fewer features, no state management parity with `aws` provider resources |
| Direct API calls via `null_resource` | Fragile, no state tracking, no drift detection |

### Sources

- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_agent` (providerDocID 11820630)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_agent_action_group` (providerDocID 11820631)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_agent_alias` (providerDocID 11820632)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_agent_collaborator` (providerDocID 11820633)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_agent_knowledge_base_association` (providerDocID 11820634)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_data_source` (providerDocID 11820635)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagent_knowledge_base` (providerDocID 11820637)
- Terraform AWS Provider docs v6.38.0: `aws_bedrock_guardrail` (providerDocID 11820625)
- Terraform AWS Provider docs v6.38.0: `aws_bedrock_guardrail_version` (providerDocID 11820626)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagentcore_agent_runtime` (providerDocID 11820639)
- Terraform AWS Provider docs v6.38.0: `aws_bedrockagentcore_code_interpreter` (providerDocID 11820643)
- Terraform Registry Module: Flaconi/bedrock-agent/aws v1.2.1
- AWS Bedrock Agents documentation: https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html
- AWS Bedrock Advanced Prompts: https://docs.aws.amazon.com/bedrock/latest/userguide/advanced-prompts.html
