# Module Design: terraform-aws-bedrock-agentcore

**Branch**: feat/001-bedrock-agentcore
**Date**: 2026-03-26
**Status**: Draft
**Provider**: hashicorp/aws >= 6.0
**Terraform**: >= 1.7

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Resources & Architecture](#2-resources--architecture)
3. [Interface Contract](#3-interface-contract)
4. [Security Controls](#4-security-controls)
5. [Test Scenarios](#5-test-scenarios)
6. [Implementation Checklist](#6-implementation-checklist)
7. [Open Questions](#7-open-questions)

---

## 1. Purpose & Requirements

This module provisions a fully operational Amazon Bedrock Agent runtime environment. It creates an AI agent backed by a configurable foundation model with conversation memory, tool execution via action groups, optional knowledge base integration for retrieval-augmented generation, an optional API gateway for external invocation, and built-in observability. The module targets platform teams and application developers who need a production-ready, security-hardened AI agent deployment without manual console configuration. It solves the problem of assembling the many interdependent Bedrock Agent resources (agent, alias, roles, action groups, knowledge bases, guardrails, logging) into a single, validated, repeatable infrastructure unit.

**Scope boundary**: The following are explicitly OUT of scope:

- Lambda function code and deployment packages -- consumers bring their own Lambda ARNs
- S3 buckets for knowledge base data sources -- consumers bring their own
- OpenSearch Serverless collections and indexes -- consumers bring their own collection ARN
- VPC and networking configuration
- Foundation model access enablement (must be done in the AWS console or via separate automation before using this module)
- Data source ingestion sync (the module creates the data source configuration but does not trigger `StartIngestionJob`)
- Multi-agent collaboration (supervisor/collaborator patterns)
- The newer `aws_bedrockagentcore_*` container runtime resources (separate service with different use case)

### Requirements

**Functional requirements** -- what the module must do (from Phase 1 clarification):

- FR-1: Provision an AI agent runtime that invokes a caller-specified foundation model with a caller-provided instruction prompt
- FR-2: Support conversation memory with configurable session summary retention so that agent context persists across interactions
- FR-3: Accept one or more tool definitions (action groups) backed by Lambda functions, API schemas, or function schemas, enabling the agent to take external actions
- FR-4: Enable a code interpreter sandbox by default so the agent can safely generate and execute Python code
- FR-5: Optionally integrate a knowledge base for retrieval-augmented generation when the caller provides a vector store endpoint and embedding model
- FR-6: Optionally expose the agent via an HTTP API endpoint with throttling and usage controls for external consumers
- FR-7: Produce a versioned agent alias suitable for runtime invocation, automatically prepared on every apply
- FR-8: Optionally associate content-filtering guardrails for responsible AI controls, either referencing an existing guardrail or creating a new one
- FR-9: Enforce that at least one agent capability (code interpreter, knowledge base, or action groups) is enabled -- an empty agent is not permitted

**Non-functional requirements** -- constraints like compliance, performance, availability:

- NFR-1: All data at rest must be encrypted with a customer-managed KMS key; this must not be disableable
- NFR-2: CloudWatch logging for agent invocations must always be enabled; this must not be disableable
- NFR-3: IAM roles must follow least-privilege principles -- model invocation scoped to the declared foundation model only, with confused-deputy protections
- NFR-4: Session data must respect a configurable idle TTL to limit data retention exposure
- NFR-5: All taggable resources must carry Environment, Owner, CostCenter, Project, Name, and ManagedBy tags
- NFR-6: The module must be consumable with minimal required inputs (agent name, foundation model, instruction, and three tag values)
- NFR-7: Optional features must not create resources when disabled -- zero cost for unused capabilities
- NFR-8: The module must support AWS provider >= 6.0 and Terraform >= 1.7

---

## 2. Resources & Architecture

### Architectural Decisions

**AD-1: Use `aws_bedrockagent_*` resource family (not `aws_bedrockagentcore_*`)**: The standard Bedrock Agent resources.
*Rationale*: The `aws_bedrockagent_*` resources are stable, well-documented in provider v6.38.0, and cover the standard agent use case. The `aws_bedrockagentcore_*` resources are for a separate containerized agent hosting model (MCP/A2A protocols) and represent a different service with different IAM principals. *Source*: research-provider.md -- "These are distinct from the `bedrockagent_*` resources and represent a container-based agent hosting model". *Rejected*: `aws_bedrockagentcore_*` resources (different service, different IAM trust, not needed for standard Bedrock Agents); `awscc_bedrock_agent` (less mature Cloud Control provider, no state management parity).

**AD-2: Use API Gateway v2 (HTTP API) for optional API endpoint (not AgentCore Gateway)**: Traditional API Gateway v2 with IAM authorization.
*Rationale*: AgentCore Gateway (`aws_bedrockagentcore_gateway`) requires the `bedrock-agentcore.amazonaws.com` service principal and is designed for MCP protocol -- it is architecturally separate from Bedrock Agents. API Gateway v2 is the established pattern for exposing Bedrock Agents via HTTP, is available in all Bedrock regions, and integrates naturally with IAM authorization. *Source*: research-aws-bestpractices.md Section 5 -- "AgentCore Gateway as Native HTTP Endpoint ... replaces the traditional API Gateway + Lambda proxy pattern". research-registry.md Section 5 notes the Gateway only supports MCP protocol currently. *Rejected*: AgentCore Gateway (requires MCP protocol, different service principal, limited regional availability); API Gateway REST API (v1 is more expensive and heavier for this use case).

**AD-3: `prepare_agent` strategy -- disable on agent, enable on last dependent resource**: Set `prepare_agent = false` on the agent resource and on intermediate action groups; let only the alias creation trigger final preparation.
*Rationale*: When creating agent and action groups in the same apply, the agent may be prepared before action groups attach if both have `prepare_agent = true`. Setting it to `false` on intermediaries and relying on alias creation (which triggers preparation) ensures all components are attached before the agent is built. *Source*: research-provider.md -- "If creating both agent and action group in the same apply, the agent may not be fully prepared when the action group tries to prepare it again"; research-edge-cases.md Section 2 -- "Set `prepare_agent = false` on the agent resource when action groups or knowledge base associations will be created in the same apply". *Rejected*: `prepare_agent = true` everywhere (race condition on first apply); `null_resource` with `local-exec` (fragile, no state tracking).

**AD-4: Module creates KMS key by default; consumers may bring their own**: The module creates a KMS key with proper Bedrock service grants unless the consumer provides an external key ARN.
*Rationale*: KMS encryption is mandatory (NFR-1). Creating a key internally ensures correct key policy grants for `bedrock.amazonaws.com` and `logs.amazonaws.com`. Consumers with centralized key management can pass their own ARN. *Source*: research-aws-bestpractices.md Section 2 -- KMS key policy must grant Bedrock service principal `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey`, `kms:DescribeKey`, `kms:CreateGrant`; research-edge-cases.md Section 4 -- "KMS Key Policy Missing Bedrock Access" failure scenario. *Rejected*: AWS-managed encryption only (does not meet NFR-1 for customer-managed keys); always require external key (adds friction for minimal deployments).

**AD-5: Module creates Lambda permissions but not Lambda functions**: For action groups with Lambda executors, the module creates `aws_lambda_permission` resources to grant Bedrock invocation rights, but does NOT create the Lambda functions themselves.
*Rationale*: Lambda functions have independent deployment lifecycles, packaging concerns, and code management that are outside the scope of an infrastructure module. However, the `aws_lambda_permission` resource-based policy is a required wiring step that belongs with the agent configuration. *Source*: research-provider.md Section on Lambda permissions -- "Lambda must grant `bedrock.amazonaws.com` invoke permission"; research-edge-cases.md Section 4 -- "Action group creation succeeds but agent invocation fails with permission errors". *Rejected*: Creating Lambda functions (out of scope, different lifecycle); omitting Lambda permissions entirely (consumers would forget, leading to runtime failures).

**AD-6: Knowledge base requires consumers to provide OpenSearch Serverless collection ARN and vector index configuration**: The module creates the knowledge base, data source, and agent association but does NOT create the OpenSearch Serverless collection.
*Rationale*: OpenSearch Serverless requires coordinating four separate resources (encryption policy, network policy, collection, data access policy) with their own security and lifecycle concerns. The 8 supported vector store backends make wrapping all of them impractical. The collection is a shared resource that may serve multiple knowledge bases. *Source*: research-aws-bestpractices.md Section 4 -- "A complete knowledge base with OpenSearch Serverless requires four coordinated resources"; research-registry.md Section 4 -- "Accept pre-existing vector store configuration... Do NOT create the vector store -- it is a separate concern". *Rejected*: Creating the full OpenSearch stack (too tightly coupled, single-backend lock-in); supporting all 8 backends (impractical interface complexity).

**AD-7: Action groups defined as a list of objects variable**: Accept action group definitions as a `list(object)` with each object specifying name, executor type, and schema.
*Rationale*: Action groups are ordered by the agent's orchestration and have a natural list structure. Each definition needs multiple fields (name, description, Lambda ARN or return-control, api_schema or function_schema). A typed object variable with optional fields provides validation while keeping the interface manageable. `for_each` with `tomap` internally provides stable resource addresses. *Source*: research-registry.md Section 3 -- Pattern A (kogunlowo123) and Pattern C (provider native) for action group handling; research-provider.md on `function_schema` and `api_schema` mutually exclusive blocks. *Rejected*: `map(object)` (action groups do not have natural unique keys beyond name); separate variables per action group (does not scale); single Lambda ARN only (too limiting per CloudPediaAI pattern).

**AD-8: Guardrail bring-your-own or module-created**: Accept an existing guardrail ID/version OR a guardrail configuration object to create one -- mutually exclusive.
*Rationale*: Guardrails may be shared across multiple agents and managed centrally, or may be agent-specific. The Flaconi/bedrock-agent module demonstrates this dual pattern effectively. *Source*: research-registry.md Section 1.3 -- "Bring your own guardrail: `guardrail_id` + `guardrail_version` for existing guardrails, OR `guardrail_config` object to create one -- mutually exclusive pattern". *Rejected*: Always create a guardrail (wasteful when shared); always require BYO (adds friction for simple deployments).

### Resource Inventory

| Resource Type | Logical Name | Conditional | Depends On | Key Configuration | Schema Notes |
|---|---|---|---|---|---|
| `aws_kms_key` | `this` | `kms_key_arn == null` (always when no BYO) | -- | `description`, `enable_key_rotation = true`, `deletion_window_in_days = 30`, key policy grants for `bedrock.amazonaws.com` and `logs.amazonaws.com` | -- |
| `aws_kms_alias` | `this` | `kms_key_arn == null` | `aws_kms_key.this` | `name = "alias/bedrock-agent-{agent_name}"` | -- |
| `aws_iam_role` | `agent` | always | -- | Trust policy: `bedrock.amazonaws.com` with `aws:SourceAccount` and `AWS:SourceArn` confused-deputy conditions | -- |
| `aws_iam_role_policy` | `agent` | always | `aws_iam_role.agent` | `bedrock:InvokeModel` scoped to specific `foundation_model` ARN pattern; conditional `bedrock:Retrieve` for KB; conditional `bedrock:ApplyGuardrail` | -- |
| `aws_bedrockagent_agent` | `this` | always | `aws_iam_role.agent`, `aws_iam_role_policy.agent` | `prepare_agent = false`, `foundation_model`, `instruction`, `customer_encryption_key_arn`, `idle_session_ttl_in_seconds`, `skip_resource_in_use_check = true`; dynamic `guardrail_configuration`, `memory_configuration` | `guardrail_configuration` is list, `memory_configuration` is list |
| `aws_bedrockagent_agent_action_group` | `code_interpreter` | `enable_code_interpreter` | `aws_bedrockagent_agent.this` | `parent_action_group_signature = "AMAZON.CodeInterpreter"`, `agent_version = "DRAFT"`, `prepare_agent = false` | -- |
| `aws_bedrockagent_agent_action_group` | `custom` | `length(action_group_definitions) > 0` (for_each) | `aws_bedrockagent_agent.this` | `agent_version = "DRAFT"`, `prepare_agent = false`; dynamic `action_group_executor`, `api_schema`, `function_schema` based on definition type | `function_schema` uses `map_block_key` for parameter names |
| `aws_lambda_permission` | `action_group` | action groups with lambda ARNs (for_each) | `aws_bedrockagent_agent.this` | `action = "lambda:InvokeFunction"`, `principal = "bedrock.amazonaws.com"`, `source_arn` scoped to agent ARN | -- |
| `aws_iam_role` | `knowledge_base` | `enable_knowledge_base` | -- | Trust policy: `bedrock.amazonaws.com` with confused-deputy conditions | -- |
| `aws_iam_role_policy` | `knowledge_base` | `enable_knowledge_base` | `aws_iam_role.knowledge_base` | `bedrock:InvokeModel` on embedding model, `aoss:APIAccessAll` on collection ARN, `s3:GetObject`+`s3:ListBucket` on data source bucket | -- |
| `aws_bedrockagent_knowledge_base` | `this` | `enable_knowledge_base` | `aws_iam_role.knowledge_base`, `aws_iam_role_policy.knowledge_base` | `knowledge_base_configuration.type = "VECTOR"`, `storage_configuration.type = "OPENSEARCH_SERVERLESS"`, `customer_encryption_key_arn` | `knowledge_base_configuration` and `storage_configuration` are ForceNew |
| `aws_bedrockagent_data_source` | `this` | `enable_knowledge_base` | `aws_bedrockagent_knowledge_base.this` | `data_source_configuration.type = "S3"`, `server_side_encryption_configuration.kms_key_arn` | `vector_ingestion_configuration` is ForceNew |
| `aws_bedrockagent_agent_knowledge_base_association` | `this` | `enable_knowledge_base` | `aws_bedrockagent_agent.this`, `aws_bedrockagent_knowledge_base.this` | `knowledge_base_state = "ENABLED"`, `agent_version = "DRAFT"`, `description` is semantically meaningful | -- |
| `aws_bedrockagent_agent_alias` | `this` | always | `aws_bedrockagent_agent.this`, all action groups, KB association | `agent_alias_name = "live"`, no `routing_configuration` (auto-latest); this is the LAST resource and triggers preparation | -- |
| `aws_bedrock_guardrail` | `this` | `guardrail_config != null` | -- | `blocked_input_messaging`, `blocked_outputs_messaging`, `kms_key_arn`; dynamic `content_policy_config`, `topic_policy_config`, `sensitive_information_policy_config`, `word_policy_config` | `content_policy_config.filters_config` is set |
| `aws_bedrock_guardrail_version` | `this` | `guardrail_config != null` | `aws_bedrock_guardrail.this` | `skip_destroy = true` to preserve old versions | -- |
| `aws_cloudwatch_log_group` | `this` | always | -- | `/aws/bedrock/agent/{agent_name}`, `retention_in_days`, `kms_key_id` for log encryption | -- |
| `aws_apigatewayv2_api` | `this` | `enable_api_gateway` | -- | `protocol_type = "HTTP"`, `name` | -- |
| `aws_apigatewayv2_stage` | `this` | `enable_api_gateway` | `aws_apigatewayv2_api.this` | `name = "$default"`, `auto_deploy = true`, `default_route_settings` with throttling (`burst_limit`, `rate_limit`) | `default_route_settings` is list |

---

## 3. Interface Contract

### Inputs

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|---|---|---|---|---|---|---|
| `agent_name` | `string` | Yes | -- | `length >= 1 && length <= 100 && can(regex("^[a-zA-Z0-9_-]+$", var.agent_name))` | No | Name of the Bedrock Agent. Alphanumeric, hyphens, and underscores only. |
| `foundation_model_id` | `string` | Yes | -- | `length >= 1` | No | Foundation model identifier (e.g., "anthropic.claude-3-5-sonnet-20241022-v2:0"). Model access must be enabled in the account. |
| `agent_instruction` | `string` | Yes | -- | `length >= 40 && length <= 20000` | No | Instruction prompt defining agent behavior. Must be 40-20000 characters. |
| `environment` | `string` | Yes | -- | `contains(["dev", "staging", "prod"], var.environment)` | No | Deployment environment name. Must be one of: dev, staging, prod. |
| `owner` | `string` | Yes | -- | `length >= 1` | No | Team or individual responsible for this agent. Used in Owner tag. |
| `cost_center` | `string` | Yes | -- | `length >= 1` | No | Cost center code for billing attribution. Used in CostCenter tag. |
| `idle_session_ttl` | `number` | No | `600` | `var.idle_session_ttl >= 60 && var.idle_session_ttl <= 3600` | No | Idle session timeout in seconds. Agent sessions are terminated after this period of inactivity. |
| `enable_code_interpreter` | `bool` | No | `true` | -- | No | Enable the code interpreter sandbox for Python code execution. |
| `enable_memory` | `bool` | No | `false` | -- | No | Enable conversation memory with session summaries for context persistence across sessions. |
| `memory_storage_days` | `number` | No | `30` | `var.memory_storage_days >= 0 && var.memory_storage_days <= 30` | No | Number of days to retain conversation memory. Only used when memory is enabled. |
| `enable_knowledge_base` | `bool` | No | `false` | -- | No | Enable knowledge base for retrieval-augmented generation. Requires opensearch_collection_arn and knowledge_base_s3_bucket_arn. |
| `knowledge_base_s3_bucket_arn` | `string` | No | `null` | `var.knowledge_base_s3_bucket_arn == null \|\| can(regex("^arn:aws:s3:::", var.knowledge_base_s3_bucket_arn))` | No | ARN of the S3 bucket containing knowledge base source documents. Required when enable_knowledge_base is true. |
| `knowledge_base_embedding_model` | `string` | No | `"amazon.titan-embed-text-v2:0"` | `contains(["amazon.titan-embed-text-v2:0", "amazon.titan-embed-text-v1", "cohere.embed-english-v3", "cohere.embed-multilingual-v3"], var.knowledge_base_embedding_model)` | No | Embedding model for knowledge base vector generation. |
| `knowledge_base_description` | `string` | No | `"Knowledge base for agent context"` | `length >= 1 && length <= 200` | No | Description of the knowledge base purpose. The agent uses this description to decide when to query the knowledge base. |
| `opensearch_collection_arn` | `string` | No | `null` | `var.opensearch_collection_arn == null \|\| can(regex("^arn:aws:aoss:", var.opensearch_collection_arn))` | No | ARN of the OpenSearch Serverless collection for knowledge base vector storage. Required when enable_knowledge_base is true. |
| `opensearch_vector_index_name` | `string` | No | `"bedrock-knowledge-base-default-index"` | `length >= 1` | No | Name of the vector index in the OpenSearch Serverless collection. |
| `action_group_definitions` | `list(object({name=string, description=optional(string,""), lambda_arn=optional(string), custom_control=optional(string), api_schema_payload=optional(string), api_schema_s3_bucket=optional(string), api_schema_s3_key=optional(string), function_schema=optional(any)}))` | No | `[]` | -- | No | List of action group definitions. Each must specify either lambda_arn or custom_control for execution, and optionally api_schema or function_schema for the API contract. |
| `enable_api_gateway` | `bool` | No | `false` | -- | No | Enable an HTTP API Gateway endpoint for external agent invocation with IAM authorization. |
| `api_throttle_rate_limit` | `number` | No | `100` | `var.api_throttle_rate_limit >= 1 && var.api_throttle_rate_limit <= 10000` | No | API Gateway steady-state request rate limit (requests per second). |
| `api_throttle_burst_limit` | `number` | No | `50` | `var.api_throttle_burst_limit >= 1 && var.api_throttle_burst_limit <= 5000` | No | API Gateway burst request limit (concurrent requests). |
| `guardrail_id` | `string` | No | `null` | `var.guardrail_id == null \|\| length(var.guardrail_id) >= 1` | No | ID of an existing Bedrock Guardrail to associate with the agent. Mutually exclusive with guardrail_config. |
| `guardrail_version` | `string` | No | `null` | `var.guardrail_version == null \|\| can(regex("^[0-9]+$", var.guardrail_version))` | No | Version number of the existing guardrail. Required when guardrail_id is provided. |
| `guardrail_config` | `object({name=string, blocked_input_messaging=optional(string,"Sorry, I cannot process that request."), blocked_outputs_messaging=optional(string,"Sorry, I cannot provide that response."), content_filters=optional(list(object({type=string, input_strength=optional(string,"HIGH"), output_strength=optional(string,"HIGH")})),[]), topic_denials=optional(list(object({name=string, definition=string, examples=optional(list(string),[])}))[]), pii_filters=optional(list(object({type=string, action=optional(string,"BLOCK")})),[])})` | No | `null` | -- | No | Configuration to create a new guardrail. Mutually exclusive with guardrail_id. |
| `kms_key_arn` | `string` | No | `null` | `var.kms_key_arn == null \|\| can(regex("^arn:aws:kms:", var.kms_key_arn))` | No | ARN of an existing KMS key for encryption at rest. If null, the module creates a KMS key with proper Bedrock service grants. |
| `log_retention_days` | `number` | No | `90` | `contains([1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,2192,2557,2922,3288,3653], var.log_retention_days)` | No | CloudWatch log group retention period in days. Must be a valid CloudWatch retention value. |
| `tags` | `map(string)` | No | `{}` | -- | No | Additional tags to apply to all taggable resources. Merged with required tags; consumer tags take precedence. |

### Outputs

| Output | Type | Conditional On | Description |
|---|---|---|---|
| `agent_id` | `string` | always | Unique identifier of the Bedrock Agent |
| `agent_arn` | `string` | always | Full ARN of the Bedrock Agent |
| `agent_alias_id` | `string` | always | Identifier of the agent alias used for invocation |
| `agent_alias_arn` | `string` | always | Full ARN of the agent alias |
| `agent_role_arn` | `string` | always | ARN of the IAM role used by the agent |
| `knowledge_base_id` | `string` | `enable_knowledge_base` | Identifier of the knowledge base (null when disabled) |
| `knowledge_base_arn` | `string` | `enable_knowledge_base` | ARN of the knowledge base (null when disabled) |
| `api_endpoint` | `string` | `enable_api_gateway` | HTTP API Gateway endpoint URL (null when disabled) |
| `kms_key_arn` | `string` | always | ARN of the KMS key used for encryption (module-created or BYO) |
| `log_group_name` | `string` | always | Name of the CloudWatch log group |
| `guardrail_id` | `string` | `guardrail_config != null` | ID of the module-created guardrail (null when using BYO or no guardrail) |
| `guardrail_version` | `string` | `guardrail_config != null` | Version number of the module-created guardrail (null when using BYO or no guardrail) |

---

## 4. Security Controls

| Control | Enforcement | Configurable? | Reference |
|---|---|---|---|
| Encryption at rest | Customer-managed KMS key applied to agent (`customer_encryption_key_arn`), knowledge base data source (`server_side_encryption_configuration`), guardrail (`kms_key_arn`), and CloudWatch logs (`kms_key_id`). Module creates KMS key with Bedrock service grants if no external key provided. **Not disableable** -- encryption is always-on because AI agent session data and conversation logs are sensitive by nature and must be protected to meet compliance requirements. | No: hardcoded always-on | CIS AWS 2.8, AWS Well-Architected SEC08-BP02 |
| Encryption in transit | Bedrock API communications use TLS 1.2+ enforced by the AWS service endpoint. API Gateway stage enforces HTTPS-only (no `disable_execute_api_endpoint` override). No module configuration needed -- AWS manages the transport layer. | N/A: platform-enforced by AWS Bedrock service | AWS Well-Architected SEC09-BP02 |
| Public access | API Gateway is disabled by default (`enable_api_gateway = false`). When enabled, IAM authorization is enforced -- no anonymous access. No public endpoints are created by default. | Yes: `enable_api_gateway` (default `false`) | CIS AWS 1.16, AWS Well-Architected SEC05-BP02 |
| IAM least privilege | Agent execution role scoped to specific foundation model ARN via `bedrock:InvokeModel` on `arn:aws:bedrock:{region}::foundation-model/{model_id}`. Confused-deputy protections with `aws:SourceAccount` and `AWS:SourceArn` conditions. Knowledge base role scoped to specific collection ARN and embedding model. Lambda permissions scoped to specific function ARN and agent source ARN. No wildcard (`*`) resource permissions. | No: hardcoded least-privilege. The IAM policy is dynamically scoped to the specific model, KB, and Lambda ARNs declared in the module inputs. Broadening requires passing different inputs, not disabling controls. | CIS AWS 1.22, AWS Well-Architected SEC03-BP06 |
| Logging | CloudWatch log group always created with configurable retention. Log group is encrypted with the same KMS key as other resources. **Not disableable** -- logging is mandatory for audit, debugging, and compliance. Omitting logs for an AI agent would eliminate observability into model invocations and responses. | No: hardcoded always-on. Retention is configurable via `log_retention_days` (default 90). | CIS AWS 3.1, AWS Well-Architected SEC04-BP01 |
| Tagging | All taggable resources receive required tags: `Name`, `ManagedBy = "terraform"`, `Environment`, `Owner`, `CostCenter`, `Project = agent_name`. Consumer-provided tags merged via `merge()` with consumer tags taking precedence. | Yes: additional tags via `tags` variable. Required tags are enforced via required variables. | AWS Well-Architected COST02-BP04 |

---

## 5. Test Scenarios

### Test Strategy

- **Module source**: Tests run against the **root module directly** -- do NOT use `module {}` blocks in `run` blocks. Assert on `resource_type.resource_name.attribute`, not `module.name.resource_type.attribute`.
- **Unit tests**: Use `mock_provider "aws" {}` with `command = plan`. Add `mock_data` blocks for `data.aws_caller_identity`, `data.aws_region`, and `data.aws_partition` data sources (needed for IAM policy ARN construction). Fast, deterministic, no credentials needed. Run during every CI build.
- **Mock data sources**: The module uses `data.aws_caller_identity.current`, `data.aws_region.current`, and `data.aws_partition.current` for constructing ARNs in IAM policies. These require `mock_data` blocks in the mock provider configuration.
- **Acceptance tests**: Use real providers with `command = plan`. Validates plan output against real AWS APIs without creating resources. Requires credentials. Not run during this workflow.
- **Integration tests**: Use real providers with `command = apply`. Creates and destroys real infrastructure. Requires credentials. Not run during this workflow.
- **Plan-time limitations (unit tests only)**: `command = plan` with mock providers means certain attributes are unknown -- provider-generated values (ARNs, endpoints, IDs) and cross-resource references (e.g., `agent_id` on dependent resources, `kms_key_id` on log group from KMS key). Mark such assertions with `[plan-unknown]` so the test writer can substitute resource-existence checks.

### Unit Tests

#### Scenario: Secure Defaults (basic)

**Purpose**: Verify the module works with minimal required inputs, code interpreter is enabled by default, and all security controls are active.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
agent_name         = "test-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction  = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise and accurate in your responses."
environment        = "dev"
owner              = "platform-team"
cost_center        = "CC-1234"
```

**Assertions**:
- Agent is created with correct name -- `aws_bedrockagent_agent.this.agent_name == "test-agent"`
- Agent uses specified foundation model -- `aws_bedrockagent_agent.this.foundation_model == "anthropic.claude-3-5-sonnet-20241022-v2:0"`
- Agent instruction is set -- `aws_bedrockagent_agent.this.instruction == "You are a helpful assistant that answers questions about cloud infrastructure. Be concise and accurate in your responses."`
- Agent prepare_agent is false (alias handles preparation) -- `aws_bedrockagent_agent.this.prepare_agent == false`
- Agent skip_resource_in_use_check is true -- `aws_bedrockagent_agent.this.skip_resource_in_use_check == true`
- Agent idle session TTL defaults to 600 -- `aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 600`
- KMS key is created (no BYO) -- `length(aws_kms_key.this) == 1`
- KMS key rotation is enabled -- `aws_kms_key.this[0].enable_key_rotation == true`
- Agent encryption key is set -- `aws_bedrockagent_agent.this.customer_encryption_key_arn` `[plan-unknown]`
- Code interpreter action group is created by default -- `length(aws_bedrockagent_agent_action_group.code_interpreter) == 1`
- Code interpreter uses correct signature -- `aws_bedrockagent_agent_action_group.code_interpreter[0].parent_action_group_signature == "AMAZON.CodeInterpreter"`
- Agent alias is created -- `length(aws_bedrockagent_agent_alias.this) == 1`
- Agent alias name is "live" -- `aws_bedrockagent_agent_alias.this.agent_alias_name == "live"`
- CloudWatch log group is created -- `length(aws_cloudwatch_log_group.this) == 1`
- Log retention defaults to 90 days -- `aws_cloudwatch_log_group.this.retention_in_days == 90`
- Agent role is created -- `length(aws_iam_role.agent) == 1`
- No knowledge base resources when disabled -- `length(aws_bedrockagent_knowledge_base.this) == 0`
- No API gateway when disabled -- `length(aws_apigatewayv2_api.this) == 0`
- No guardrail when not configured -- `length(aws_bedrock_guardrail.this) == 0`
- Memory is disabled by default -- `length(aws_bedrockagent_agent.this.memory_configuration) == 0`
- Agent tags include Environment -- `aws_bedrockagent_agent.this.tags["Environment"] == "dev"`
- Agent tags include ManagedBy -- `aws_bedrockagent_agent.this.tags["ManagedBy"] == "terraform"`
- Agent tags include Owner -- `aws_bedrockagent_agent.this.tags["Owner"] == "platform-team"`
- Agent tags include CostCenter -- `aws_bedrockagent_agent.this.tags["CostCenter"] == "CC-1234"`

#### Scenario: Full Features (complete)

**Purpose**: Verify all features enabled, all optional resources created, all outputs populated.
**Command**: `plan` (mock providers)

**Inputs**:
```hcl
agent_name                  = "full-featured-agent"
foundation_model_id         = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction           = "You are a comprehensive assistant with access to knowledge bases, tools, and code execution capabilities. Use all available resources to help users."
environment                 = "prod"
owner                       = "ml-engineering"
cost_center                 = "CC-5678"
idle_session_ttl            = 1800
enable_code_interpreter     = true
enable_memory               = true
memory_storage_days         = 14
enable_knowledge_base       = true
knowledge_base_s3_bucket_arn = "arn:aws:s3:::my-kb-documents"
knowledge_base_embedding_model = "amazon.titan-embed-text-v2:0"
knowledge_base_description  = "Product documentation and FAQs"
opensearch_collection_arn   = "arn:aws:aoss:us-east-1:123456789012:collection/abc123def456"
opensearch_vector_index_name = "product-docs-index"
action_group_definitions = [
  {
    name        = "lookup-order"
    description = "Look up customer order status"
    lambda_arn  = "arn:aws:lambda:us-east-1:123456789012:function:order-lookup"
    api_schema_payload = "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"Order API\",\"version\":\"1.0\"},\"paths\":{}}"
  }
]
enable_api_gateway       = true
api_throttle_rate_limit  = 500
api_throttle_burst_limit = 200
guardrail_config = {
  name = "full-guardrail"
  content_filters = [
    { type = "HATE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "VIOLENCE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "PROMPT_ATTACK", input_strength = "HIGH", output_strength = "HIGH" }
  ]
  pii_filters = [
    { type = "EMAIL", action = "ANONYMIZE" },
    { type = "PHONE", action = "BLOCK" }
  ]
}
log_retention_days       = 365
tags = { Team = "ml-engineering" }
```

**Assertions**:
- Agent idle session TTL set to 1800 -- `aws_bedrockagent_agent.this.idle_session_ttl_in_seconds == 1800`
- Memory is enabled with SESSION_SUMMARY -- `aws_bedrockagent_agent.this.memory_configuration[0].enabled_memory_types == toset(["SESSION_SUMMARY"])`
- Memory storage days set to 14 -- `aws_bedrockagent_agent.this.memory_configuration[0].storage_days == 14`
- Knowledge base is created -- `length(aws_bedrockagent_knowledge_base.this) == 1`
- Knowledge base role is created -- `length(aws_iam_role.knowledge_base) == 1`
- Data source is created -- `length(aws_bedrockagent_data_source.this) == 1`
- KB association is created -- `length(aws_bedrockagent_agent_knowledge_base_association.this) == 1`
- KB association description is semantically set -- `aws_bedrockagent_agent_knowledge_base_association.this[0].description == "Product documentation and FAQs"`
- Custom action group is created -- `length(aws_bedrockagent_agent_action_group.custom) == 1`
- Lambda permission is created for action group -- `length(aws_lambda_permission.action_group) == 1`
- Code interpreter is still created alongside custom groups -- `length(aws_bedrockagent_agent_action_group.code_interpreter) == 1`
- API gateway is created -- `length(aws_apigatewayv2_api.this) == 1`
- API gateway uses HTTP protocol -- `aws_apigatewayv2_api.this[0].protocol_type == "HTTP"`
- API gateway stage is created -- `length(aws_apigatewayv2_stage.this) == 1`
- Guardrail is created -- `length(aws_bedrock_guardrail.this) == 1`
- Guardrail version is created -- `length(aws_bedrock_guardrail_version.this) == 1`
- Guardrail blocked input messaging set -- `aws_bedrock_guardrail.this[0].blocked_input_messaging == "Sorry, I cannot process that request."`
- Log retention set to 365 -- `aws_cloudwatch_log_group.this.retention_in_days == 365`
- Custom tag propagated -- `aws_bedrockagent_agent.this.tags["Team"] == "ml-engineering"`
- Environment tag is prod -- `aws_bedrockagent_agent.this.tags["Environment"] == "prod"`
- Agent alias exists (triggers preparation) -- `length(aws_bedrockagent_agent_alias.this) == 1`

#### Scenario: Feature Interactions (edge cases)

**Purpose**: Verify non-obvious combinations of feature toggles produce correct behavior.
**Command**: `plan` (mock providers)

**Sub-scenario: Code interpreter disabled with action groups present**
**Inputs**:
```hcl
agent_name          = "no-code-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are an assistant that uses tools to help users. Do not execute code directly."
environment         = "dev"
owner               = "platform-team"
cost_center         = "CC-1234"
enable_code_interpreter = false
action_group_definitions = [
  {
    name        = "search-api"
    description = "Search external API"
    lambda_arn  = "arn:aws:lambda:us-east-1:123456789012:function:search"
    api_schema_payload = "{\"openapi\":\"3.0.0\",\"info\":{\"title\":\"Search\",\"version\":\"1.0\"},\"paths\":{}}"
  }
]
```
**Assertions**:
- Code interpreter is NOT created -- `length(aws_bedrockagent_agent_action_group.code_interpreter) == 0`
- Custom action group IS created -- `length(aws_bedrockagent_agent_action_group.custom) == 1`
- Lambda permission IS created -- `length(aws_lambda_permission.action_group) == 1`

**Sub-scenario: Knowledge base enabled without code interpreter or action groups**
**Inputs**:
```hcl
agent_name                   = "kb-only-agent"
foundation_model_id          = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction            = "You are a knowledge assistant. Answer questions using only the provided knowledge base."
environment                  = "dev"
owner                        = "platform-team"
cost_center                  = "CC-1234"
enable_code_interpreter      = false
enable_knowledge_base        = true
knowledge_base_s3_bucket_arn = "arn:aws:s3:::docs-bucket"
opensearch_collection_arn    = "arn:aws:aoss:us-east-1:123456789012:collection/xyz789"
```
**Assertions**:
- Knowledge base is created -- `length(aws_bedrockagent_knowledge_base.this) == 1`
- KB association is created -- `length(aws_bedrockagent_agent_knowledge_base_association.this) == 1`
- Code interpreter is NOT created -- `length(aws_bedrockagent_agent_action_group.code_interpreter) == 0`
- No custom action groups -- `length(aws_bedrockagent_agent_action_group.custom) == 0`

**Sub-scenario: BYO guardrail (ID + version) without module-created guardrail**
**Inputs**:
```hcl
agent_name          = "byo-guardrail-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are a safe assistant with externally managed content filtering."
environment         = "prod"
owner               = "platform-team"
cost_center         = "CC-1234"
guardrail_id        = "abc123"
guardrail_version   = "1"
```
**Assertions**:
- Module-created guardrail is NOT created -- `length(aws_bedrock_guardrail.this) == 0`
- Module-created guardrail version is NOT created -- `length(aws_bedrock_guardrail_version.this) == 0`
- Agent guardrail configuration references BYO ID -- `aws_bedrockagent_agent.this.guardrail_configuration[0].guardrail_identifier == "abc123"`
- Agent guardrail configuration references BYO version -- `aws_bedrockagent_agent.this.guardrail_configuration[0].guardrail_version == "1"`

**Sub-scenario: BYO KMS key instead of module-created key**
**Inputs**:
```hcl
agent_name          = "byo-kms-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are an assistant using a centrally managed encryption key."
environment         = "prod"
owner               = "platform-team"
cost_center         = "CC-1234"
kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
```
**Assertions**:
- Module KMS key is NOT created -- `length(aws_kms_key.this) == 0`
- Module KMS alias is NOT created -- `length(aws_kms_alias.this) == 0`
- Agent encryption key uses BYO ARN -- `aws_bedrockagent_agent.this.customer_encryption_key_arn == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"`

**Sub-scenario: API gateway enabled without knowledge base**
**Inputs**:
```hcl
agent_name           = "api-only-agent"
foundation_model_id  = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction    = "You are an assistant accessible via API with code execution capabilities."
environment          = "staging"
owner                = "platform-team"
cost_center          = "CC-1234"
enable_api_gateway   = true
api_throttle_rate_limit  = 200
api_throttle_burst_limit = 100
```
**Assertions**:
- API gateway is created -- `length(aws_apigatewayv2_api.this) == 1`
- API gateway stage is created -- `length(aws_apigatewayv2_stage.this) == 1`
- No knowledge base resources -- `length(aws_bedrockagent_knowledge_base.this) == 0`
- Code interpreter still active (default) -- `length(aws_bedrockagent_agent_action_group.code_interpreter) == 1`

**Sub-scenario: Memory enabled with custom storage days**
**Inputs**:
```hcl
agent_name          = "memory-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are an assistant that remembers previous conversations and builds on past interactions."
environment         = "dev"
owner               = "platform-team"
cost_center         = "CC-1234"
enable_memory       = true
memory_storage_days = 7
```
**Assertions**:
- Memory configuration is present -- `length(aws_bedrockagent_agent.this.memory_configuration) == 1`
- Memory type is SESSION_SUMMARY -- `aws_bedrockagent_agent.this.memory_configuration[0].enabled_memory_types == toset(["SESSION_SUMMARY"])`
- Memory storage days set to 7 -- `aws_bedrockagent_agent.this.memory_configuration[0].storage_days == 7`

#### Scenario: Validation Boundaries (accept)

**Purpose**: Verify validation rules accept values at the valid boundary.
**Command**: `plan` (mock providers)

**Boundary-pass cases**:
- `agent_instruction`: 40 characters (minimum valid) -> accepted. A string of exactly 40 characters passes the `length >= 40` check.
- `agent_instruction`: 20000 characters (maximum valid) -> accepted. A string of exactly 20000 characters passes the `length <= 20000` check.
- `idle_session_ttl`: `60` (minimum valid) -> accepted. The lower bound of the 60-3600 range.
- `idle_session_ttl`: `3600` (maximum valid) -> accepted. The upper bound of the 60-3600 range.
- `memory_storage_days`: `0` (minimum valid) -> accepted. Zero days disables memory retention.
- `memory_storage_days`: `30` (maximum valid) -> accepted. The upper bound of the 0-30 range.
- `log_retention_days`: `1` (minimum valid CloudWatch value) -> accepted. The smallest valid CloudWatch retention period.
- `api_throttle_rate_limit`: `1` (minimum valid) -> accepted. The lower bound.
- `api_throttle_rate_limit`: `10000` (maximum valid) -> accepted. The upper bound.
- `api_throttle_burst_limit`: `1` (minimum valid) -> accepted. The lower bound.
- `environment`: `"dev"` -> accepted. One of the three valid values.
- `environment`: `"prod"` -> accepted. One of the three valid values.
- `agent_name`: `"a"` (minimum valid, 1 char) -> accepted. Single character alphanumeric name.
- `guardrail_version`: `"1"` (minimum valid numeric string) -> accepted. Single-digit version number.

#### Scenario: Validation Errors (reject)

**Purpose**: Verify input validation rejects bad inputs.
**Command**: `plan` (mock providers)

**Expect error cases**:
- `agent_instruction`: 39 characters -> rejected. Below minimum 40-character requirement. `expect_failures = [var.agent_instruction]`
- `agent_instruction`: 20001 characters -> rejected. Exceeds maximum 20000-character limit. `expect_failures = [var.agent_instruction]`
- `idle_session_ttl`: `59` -> rejected. Below minimum 60-second threshold. `expect_failures = [var.idle_session_ttl]`
- `idle_session_ttl`: `3601` -> rejected. Exceeds maximum 3600-second threshold. `expect_failures = [var.idle_session_ttl]`
- `memory_storage_days`: `-1` -> rejected. Below minimum 0. `expect_failures = [var.memory_storage_days]`
- `memory_storage_days`: `31` -> rejected. Exceeds maximum 30 days. `expect_failures = [var.memory_storage_days]`
- `environment`: `"production"` -> rejected. Not in the allowed set [dev, staging, prod]. `expect_failures = [var.environment]`
- `log_retention_days`: `2` -> rejected. Not a valid CloudWatch retention value. `expect_failures = [var.log_retention_days]`
- `agent_name`: `"invalid agent!"` -> rejected. Contains space and special characters not matching the regex pattern. `expect_failures = [var.agent_name]`
- `kms_key_arn`: `"not-an-arn"` -> rejected. Does not match KMS ARN pattern. `expect_failures = [var.kms_key_arn]`
- `api_throttle_rate_limit`: `0` -> rejected. Below minimum 1. `expect_failures = [var.api_throttle_rate_limit]`
- `api_throttle_burst_limit`: `0` -> rejected. Below minimum 1. `expect_failures = [var.api_throttle_burst_limit]`
- `guardrail_version`: `"DRAFT"` -> rejected. Does not match numeric-only pattern. `expect_failures = [var.guardrail_version]`

### Acceptance Tests

#### Scenario: Plan Verification

**Purpose**: Verify plan output with real provider APIs -- validates computed attributes, ARN formats, and provider-resolved references that unit tests cannot check.
**Command**: `plan` (real providers)

**Inputs**:
```hcl
agent_name          = "acceptance-test-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are a helpful assistant for acceptance testing. Answer questions accurately and concisely."
environment         = "dev"
owner               = "test-team"
cost_center         = "CC-TEST"
```

**Assertions**:
- Agent ARN follows expected format -- `can(regex("^arn:aws:bedrock:", aws_bedrockagent_agent.this.agent_arn))`
- KMS key ARN follows expected format -- `can(regex("^arn:aws:kms:", aws_kms_key.this[0].arn))`
- Agent role ARN follows expected format -- `can(regex("^arn:aws:iam:", aws_iam_role.agent.arn))`
- Log group name is correct -- `aws_cloudwatch_log_group.this.name == "/aws/bedrock/agent/acceptance-test-agent"`
- Agent encryption key ARN is populated -- `aws_bedrockagent_agent.this.customer_encryption_key_arn != null`

### Integration Tests

#### Scenario: End-to-End

**Purpose**: Verify resources are created, configured correctly, and functional in AWS.
**Command**: `apply` (real providers)

**Inputs**:
```hcl
agent_name          = "integration-test-agent"
foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
agent_instruction   = "You are an integration test agent. Answer all questions with 'Integration test successful.' for verification purposes."
environment         = "dev"
owner               = "test-team"
cost_center         = "CC-TEST"
enable_code_interpreter = true
```

**Assertions**:
- Agent ID is populated -- `output.agent_id != ""`
- Agent ARN is populated -- `output.agent_arn != ""`
- Agent alias ID is populated -- `output.agent_alias_id != ""`
- Agent alias ARN is populated -- `output.agent_alias_arn != ""`
- Agent role ARN is populated -- `output.agent_role_arn != ""`
- KMS key ARN is populated -- `output.kms_key_arn != ""`
- Log group name matches expected pattern -- `output.log_group_name == "/aws/bedrock/agent/integration-test-agent"`
- Knowledge base ID is null when disabled -- `output.knowledge_base_id == null`
- API endpoint is null when disabled -- `output.api_endpoint == null`

---

## 6. Implementation Checklist

- [x] **A: Scaffold** -- Create `versions.tf` (terraform >= 1.7, aws >= 6.0), `variables.tf` (all input variables with validation blocks), `outputs.tf` (all outputs with `try()` for conditional resources), `locals.tf` (tag merging, derived values, effective KMS ARN, effective guardrail references), `data.tf` (`aws_caller_identity`, `aws_region`, `aws_partition`). Creates: `versions.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `data.tf`.

- [x] **B: Security core** -- Create KMS key with Bedrock service policy grants, KMS alias, agent IAM role with trust policy and least-privilege permissions, knowledge base IAM role (conditional). Create `kms.tf` (KMS key, alias, key policy) and `iam.tf` (agent role, agent policy, KB role, KB policy, Lambda permissions). Creates: `kms.tf`, `iam.tf`.

- [x] **C: Core agent and features** -- Create agent resource, code interpreter action group, custom action groups (for_each), knowledge base + data source + association (conditional), agent alias, CloudWatch log group, guardrail + version (conditional), API gateway + stage (conditional). Create `main.tf` (agent, alias, action groups, log group), `knowledge_base.tf` (KB, data source, association), `guardrail.tf` (guardrail, version), `api_gateway.tf` (API, stage). Creates: `main.tf`, `knowledge_base.tf`, `guardrail.tf`, `api_gateway.tf`.

- [ ] **D: Examples** -- Create `examples/basic/` (minimal agent with defaults -- main.tf, provider config, terraform.tfvars) and `examples/complete/` (all features enabled -- main.tf, provider config, terraform.tfvars). Creates: `examples/basic/main.tf`, `examples/basic/versions.tf`, `examples/complete/main.tf`, `examples/complete/versions.tf`.

- [ ] **E: Tests** -- Create unit test files with mock providers: `tests/unit_basic.tftest.hcl` (secure defaults), `tests/unit_complete.tftest.hcl` (full features), `tests/unit_edge_cases.tftest.hcl` (feature interactions), `tests/unit_validation.tftest.hcl` (validation errors + boundaries). Create acceptance and integration stubs: `tests/acceptance.tftest.hcl`, `tests/integration.tftest.hcl`. Creates: all files in `tests/`.

- [ ] **F: Polish** -- Generate README via terraform-docs, run `terraform fmt -recursive`, run `terraform validate`, run `tflint`, run `trivy config .`. Modifies: `README.md`. Validates all existing files.

---

## 7. Open Questions

None. All ambiguities were resolved during Phase 1 clarification. The following assumptions were made and documented:

- The module assumes foundation model access has been enabled in the AWS account before deployment. There is no Terraform resource to enable model access.
- Data source creation does NOT trigger ingestion sync. Consumers must call `StartIngestionJob` separately. This is documented in the module README.
- The `AMAZON.CodeInterpreter` value for `parent_action_group_signature` is supported by the AWS API but underdocumented in the Terraform provider. If a future provider version rejects this value, a provider version constraint update may be needed.
- Agent version drift is expected behavior: every preparation cycle increments the DRAFT version outside Terraform. The module uses `"DRAFT"` for all action group and KB association `agent_version` references to avoid state conflicts.
