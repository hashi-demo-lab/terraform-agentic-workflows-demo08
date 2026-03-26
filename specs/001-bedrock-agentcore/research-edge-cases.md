## Research: Edge Cases, Service Limits, and Operational Constraints for AWS Bedrock Agents / AgentCore Terraform Module Design

### Decision

Design the module with defensive defaults, explicit dependency ordering, and validation rules that prevent the most common failure scenarios -- particularly around `prepare_agent` lifecycle, instruction character limits, and the distinct resource families (Bedrock Agents vs. Bedrock AgentCore).

---

### 1. Service Quotas and Limits

#### Bedrock Agents (Classic)

| Limit | Value | Adjustable | Impact on Module |
|-------|-------|------------|------------------|
| Agent instruction length | 40 - 20,000 characters | No | Must add `validation` block on instruction variable |
| Idle session TTL | Configurable via `idle_session_ttl_in_seconds` | Yes (per agent) | Default 500s in examples; expose as variable |
| Action groups per agent | Up to 20 (default service quota) | Yes via Service Quotas | Module should accept a map/list; document limit |
| Knowledge bases per agent | Up to 2 (default service quota, adjustable) | Yes via Service Quotas | Module should accept a list; document limit |
| Agent aliases per agent | Up to 10 (default) | Yes via Service Quotas | Module can create 1 alias; document multi-alias pattern |
| API schema payload size | 100 KB inline, up to 100 KB via S3 | No | Recommend S3 for large schemas; validate or warn in docs |
| Foundation model access | Must be explicitly enabled in the account | N/A | Cannot validate in Terraform; document as prerequisite |
| Concurrent sessions | Region-dependent; default varies | Yes | Not controllable via Terraform; document for operators |

#### Bedrock AgentCore (New)

| Limit | Value | Impact on Module |
|-------|-------|------------------|
| Memory strategies per memory | Maximum 6 total | Must validate in module or document clearly |
| Built-in strategy types per memory | 1 each of SEMANTIC, SUMMARIZATION, USER_PREFERENCE | Only one of each built-in type allowed; multiple CUSTOM allowed |
| Memory event expiry duration | 7 - 365 days | Add validation block |
| Gateway interceptors | Min 1, Max 2 per gateway | Document constraint |
| Metadata allowed headers | Max 10 per direction (request/response/query) | Add validation |
| Workload identity name | 3-255 characters, alphanumeric + hyphens/periods/underscores | Add validation |
| Code interpreter network modes | PUBLIC, SANDBOX, VPC | SANDBOX requires execution_role_arn |
| Browser network modes | PUBLIC, VPC | VPC requires security_groups + subnets |

---

### 2. Resource Dependencies and Ordering

#### Bedrock Agents (Classic) -- Dependency Chain

```
aws_iam_role (agent execution role)
  -> aws_iam_role_policy (model invocation permissions)
  -> aws_bedrockagent_agent (the agent itself)
      -> aws_bedrockagent_agent_action_group (action groups; requires agent_id + agent_version=DRAFT)
      -> aws_bedrockagent_agent_knowledge_base_association (requires agent_id + knowledge_base_id)
      -> aws_bedrockagent_agent_collaborator (requires agent_id, references alias_arn of another agent)
      -> aws_bedrockagent_agent_alias (requires agent_id; triggers new agent version)
```

**Critical ordering constraints:**

1. **Agent must exist before action groups**: `aws_bedrockagent_agent_action_group` requires `agent_id` and `agent_version` (always `DRAFT`). The agent resource must be fully created first.

2. **`prepare_agent` behavior**: Both `aws_bedrockagent_agent` and `aws_bedrockagent_agent_action_group` have a `prepare_agent` argument that defaults to `true`. When `true`, the provider automatically calls `PrepareAgent` after create/update. This means:
   - If you create an agent with `prepare_agent = true`, it gets prepared immediately
   - If you then add an action group (also with `prepare_agent = true`), the agent gets re-prepared
   - **Problem**: If creating both agent and action group in the same apply, the agent may not be fully prepared when the action group tries to prepare it again
   - **Recommendation**: Set `prepare_agent = false` on the agent resource when action groups or knowledge base associations will be created in the same apply. Have only the *last* dependent resource set `prepare_agent = true`, or use a separate `null_resource` with a local-exec provisioner.

3. **Alias creation timing**: `aws_bedrockagent_agent_alias` can be created at any time after the agent exists. Creating an alias implicitly creates a new numbered agent version pointing to the current DRAFT. The alias does NOT require the agent to be in PREPARED state first -- the alias creation itself triggers preparation if needed.

4. **Knowledge base association**: `aws_bedrockagent_agent_knowledge_base_association` uses `agent_version = "DRAFT"` (forced new resource if changed). The knowledge base itself (`aws_bedrockagent_knowledge_base`) must exist before the association.

5. **Collaborator ordering**: The collaborator agent must have an alias created before the supervisor agent can reference it. This creates a cross-agent dependency: `collaborator_agent -> collaborator_alias -> supervisor_collaborator_resource`.

#### Bedrock AgentCore -- Dependency Chain

```
aws_iam_role (runtime/gateway execution role)
  -> aws_bedrockagentcore_agent_runtime
      -> aws_bedrockagentcore_agent_runtime_endpoint (requires agent_runtime_id)
  -> aws_bedrockagentcore_gateway
      -> aws_bedrockagentcore_gateway_target (requires gateway_identifier)
  -> aws_bedrockagentcore_memory
      -> aws_bedrockagentcore_memory_strategy (requires memory_id)
  -> aws_bedrockagentcore_workload_identity (standalone)
  -> aws_bedrockagentcore_browser (standalone)
  -> aws_bedrockagentcore_code_interpreter (standalone)
  -> aws_bedrockagentcore_token_vault_cmk (singleton per region)
  -> aws_bedrockagentcore_api_key_credential_provider (standalone)
  -> aws_bedrockagentcore_oauth2_credential_provider (standalone)
```

**Key constraints:**
- Gateway targets reference gateway by `gateway_identifier` (the gateway_id output)
- Memory strategies reference memory by `memory_id`
- Agent runtime endpoints reference the runtime by `agent_runtime_id`
- Token vault CMK is effectively a singleton -- defaults to `token_vault_id = "default"`
- Credential providers (API key, OAuth2) are standalone but referenced by ARN from gateway targets

---

### 3. Terraform State Management Concerns

#### Agent Version Drift

**The most significant state management issue**: The `agent_version` attribute on `aws_bedrockagent_agent` is computed and changes outside Terraform. Every time the agent is prepared (either explicitly or via action group/KB association changes), the DRAFT version increments. This means:

- `agent_version` in state may not match actual version
- This is a *read-only computed attribute* so it does not cause forced replacement
- The `prepared_at` timestamp also changes outside Terraform
- **Module design**: Do NOT use `agent_version` as an input to other resources; always use `"DRAFT"` for action groups and KB associations

#### prepare_agent Interactions with Plan/Apply

- `prepare_agent = true` (default) causes a side effect during `apply` -- it calls the PrepareAgent API
- This is not visible in `plan` output -- it happens as a post-create/post-update hook
- If preparation fails (e.g., invalid instruction, model not enabled), the resource creation still succeeds but the agent may be in `NOT_PREPARED` or `FAILED` state
- **Recommendation**: Always set `prepare_agent = true` on the final resource in the dependency chain, and `false` on intermediate resources

#### Force-Replacement Attributes

Resources that trigger replacement (not in-place update):

| Resource | Force-Replace Attributes |
|----------|-------------------------|
| `aws_bedrockagent_agent_alias` | `agent_id` |
| `aws_bedrockagent_agent_knowledge_base_association` | `agent_id`, `knowledge_base_id`, `agent_version` |
| `aws_bedrockagent_knowledge_base` | `knowledge_base_configuration`, `storage_configuration` |
| `aws_bedrockagent_data_source` | `name`, `vector_ingestion_configuration` (all sub-blocks) |
| `aws_bedrockagentcore_memory_strategy` | `memory_id`, `type`, `configuration.type` |

**Critical**: Changing the embedding model on a knowledge base (`embedding_model_arn`) forces replacement of the entire knowledge base AND requires re-ingestion of all data sources. This is extremely disruptive.

**Critical**: Changing `vector_ingestion_configuration` on a data source (chunking strategy, parsing config) forces replacement. All data must be re-ingested.

#### Import Composite IDs

Several resources use composite IDs for import, which complicates state management:

- `aws_bedrockagent_agent_action_group`: `action_group_id,agent_id,DRAFT`
- `aws_bedrockagent_agent_alias`: `alias_id,agent_id`
- `aws_bedrockagent_agent_knowledge_base_association`: `agent_id,DRAFT,knowledge_base_id`
- `aws_bedrockagent_data_source`: `data_source_id,knowledge_base_id`
- `aws_bedrockagentcore_agent_runtime_endpoint`: `agent_runtime_id,name`
- `aws_bedrockagentcore_gateway_target`: `gateway_id,target_id`
- `aws_bedrockagentcore_memory_strategy`: `memory_id,strategy_id`

**Module design**: Expose these composite IDs as outputs for import documentation.

---

### 4. Common Failure Scenarios

#### Foundation Model Not Enabled

- **Symptom**: Agent creation succeeds but preparation fails with `ValidationException`
- **Root Cause**: The foundation model (e.g., `anthropic.claude-v2`) must be explicitly enabled via the Bedrock console or API (`model-access`) before use
- **Terraform Impact**: The `aws_bedrockagent_agent` resource creates successfully (the agent record exists) but `prepare_agent` fails silently or returns an error
- **Mitigation**: Document as a prerequisite. There is no Terraform resource to enable model access -- it must be done manually or via the AWSCC provider (`awscc_bedrock_guardrail` etc.)

#### KMS Key Policy Missing Bedrock Access

- **Symptom**: `AccessDeniedException` when creating agent with `customer_encryption_key_arn`
- **Root Cause**: The KMS key policy must grant `bedrock.amazonaws.com` permission to use the key
- **Required KMS Policy Grants**: `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey`, `kms:DescribeKey`, `kms:CreateGrant` for `bedrock.amazonaws.com` principal
- **Module design**: If the module creates a KMS key, include the proper policy. If accepting an external key ARN, document the required policy.

#### Lambda Permission Issues with Action Groups

- **Symptom**: Action group creation succeeds but agent invocation fails with permission errors
- **Root Cause**: The Lambda function must have a resource-based policy allowing `bedrock.amazonaws.com` to invoke it
- **Required**: `aws_lambda_permission` with `principal = "bedrock.amazonaws.com"` and `source_arn` set to the agent ARN
- **Module design**: Either create the Lambda permission automatically or document the requirement clearly

#### Knowledge Base Sync Failures

- **Symptom**: `aws_bedrockagent_data_source` creates but data is not queryable
- **Root Cause**: Data source creation does NOT trigger ingestion sync. Sync must be triggered separately.
- **Terraform Gap**: There is NO Terraform resource to trigger data source sync (StartIngestionJob API). This must be done via AWS CLI, SDK, or a custom `null_resource` with `local-exec`.
- **Module design**: Document that data source creation is not sufficient; sync must be triggered out-of-band

#### IAM Role Propagation Delay

- **Symptom**: Intermittent `InvalidParameterException` or `AccessDeniedException` on first apply
- **Root Cause**: IAM role creation and policy attachment have eventual consistency delays
- **Mitigation**: Use `depends_on` from the agent resource to the role policy. Consider adding a `time_sleep` resource (e.g., 10-15 seconds) between role policy creation and agent creation.

#### Action Group Agent Version Lock

- **Symptom**: Error when trying to update action group after alias creation
- **Root Cause**: `agent_version` is locked to `"DRAFT"` -- the only valid value. If the provider sends a different version, the API rejects it.
- **Terraform Impact**: This is handled correctly by the provider, but worth noting that action groups can only be modified on the DRAFT version.

#### AgentCore Container Image Pull Failures

- **Symptom**: Agent runtime creation hangs or fails during container startup
- **Root Cause**: IAM role lacks ECR permissions or the container image URI is invalid
- **Required Permissions**: `ecr:GetAuthorizationToken` (on `*`), `ecr:BatchGetImage` + `ecr:GetDownloadUrlForLayer` (on the specific repo)
- **Mitigation**: Module should create the IAM role with correct ECR policies automatically

#### Gateway Target Credential Provider Mismatch

- **Symptom**: Gateway target creation fails or target invocation fails
- **Root Cause**: `credential_provider_configuration` is required for Lambda/OpenAPI/Smithy targets but must NOT be specified for `mcp_server` targets without authorization
- **Module design**: Use conditional logic based on target type

---

### 5. Region Availability

#### Bedrock Agents (Classic)

Bedrock Agents is available in the following regions (as of early 2026):

| Region | Code | Agents | Knowledge Bases | Notes |
|--------|------|--------|-----------------|-------|
| US East (N. Virginia) | us-east-1 | Yes | Yes | Broadest feature support |
| US West (Oregon) | us-west-2 | Yes | Yes | Broadest feature support |
| EU (Frankfurt) | eu-central-1 | Yes | Yes | |
| EU (Ireland) | eu-west-1 | Yes | Yes | |
| EU (London) | eu-west-2 | Yes | Limited | |
| EU (Paris) | eu-west-3 | Yes | Limited | |
| Asia Pacific (Tokyo) | ap-northeast-1 | Yes | Yes | |
| Asia Pacific (Seoul) | ap-northeast-2 | Yes | Limited | |
| Asia Pacific (Mumbai) | ap-south-1 | Yes | Limited | |
| Asia Pacific (Singapore) | ap-southeast-1 | Yes | Yes | |
| Asia Pacific (Sydney) | ap-southeast-2 | Yes | Yes | |
| Canada (Central) | ca-central-1 | Yes | Limited | |
| South America (Sao Paulo) | sa-east-1 | Yes | Limited | |

**Feature differences by region:**
- Not all foundation models are available in all regions
- OpenSearch Serverless (for knowledge base vector storage) availability varies
- Some newer features (multi-agent collaboration, flows) may only be in us-east-1 and us-west-2 initially

#### Bedrock AgentCore (New)

AgentCore is a newer service and has more limited regional availability. As of provider version 6.38.0, the resources exist but availability should be verified against the AWS documentation. Expected initial regions: us-east-1, us-west-2, with gradual expansion.

**Module design**: Do not hardcode regions. Use `data.aws_region.current` and validate prerequisites dynamically where possible.

#### Knowledge Base Vector Store Availability

| Vector Store | Available Regions |
|-------------|-------------------|
| OpenSearch Serverless | Most Bedrock regions |
| Amazon RDS (pgvector) | All regions with RDS PostgreSQL |
| Pinecone | All regions (external service) |
| Redis Enterprise Cloud | All regions (external service) |
| MongoDB Atlas | All regions (external service) |
| S3 Vectors | us-east-1, us-west-2 (new, limited) |
| Neptune Analytics | Limited regions |
| OpenSearch Managed | Most Bedrock regions |

---

### 6. Cross-Account and Multi-Region Considerations

#### Cross-Account Lambda Functions

- **Supported**: Yes, action groups can reference Lambda functions in other accounts
- **Requirements**:
  1. Lambda resource-based policy must allow `bedrock.amazonaws.com` from the agent's account
  2. The agent execution role must have `lambda:InvokeFunction` permission on the cross-account Lambda ARN
  3. Use the full ARN including the account ID

#### Cross-Account KMS Keys

- **Supported**: Yes, but the KMS key policy must grant access to the Bedrock service in the agent's account
- **Requirements**:
  1. KMS key policy must allow `kms:Decrypt`, `kms:GenerateDataKey`, `kms:DescribeKey` for `bedrock.amazonaws.com`
  2. The key policy must include a condition for the source account
  3. The agent execution role must have `kms:Decrypt` permission

#### Cross-Account Knowledge Base Access

- **Knowledge base and agent in different accounts**: Not natively supported. The knowledge base must be in the same account as the agent.
- **Data sources in different accounts**: S3 buckets in other accounts can be used as data sources if the knowledge base role has cross-account S3 permissions
- **Vector stores in different accounts**: OpenSearch Serverless collections can be shared via data access policies

#### Multi-Region Considerations

- Agents are regional resources; there is no native cross-region agent invocation
- Knowledge bases are regional; vector store data is not replicated
- For multi-region deployments, deploy separate agent stacks per region
- AgentCore Gateway targets can point to Lambda functions in any region (via full ARN), but latency will increase

---

### 7. Upgrade and Migration Paths

#### Agent Instruction Changes

- **Behavior**: In-place update. Changing `instruction` on `aws_bedrockagent_agent` triggers an update (not replacement).
- **Side Effect**: If `prepare_agent = true`, the agent is re-prepared automatically, creating a new DRAFT version.
- **Alias Impact**: Existing aliases continue pointing to their previously pinned version. A new alias creation or alias update is needed to pick up the new version.

#### Action Group Schema Changes

- **API schema (payload or S3)**: In-place update. The action group is updated without replacement.
- **Function schema changes**: In-place update.
- **Switching between api_schema and function_schema**: Requires replacement (cannot switch schema types on an existing action group).
- **Re-preparation**: If `prepare_agent = true` on the action group, the agent is re-prepared after schema changes.

#### Knowledge Base Embedding Model Change

- **Behavior**: FORCES REPLACEMENT of the entire knowledge base (`embedding_model_arn` is in `knowledge_base_configuration` which is `Forces new resource`).
- **Impact**: All data sources must be recreated and re-ingested.
- **Migration Path**:
  1. Create new knowledge base with new embedding model
  2. Create new data sources and trigger ingestion
  3. Update agent KB associations to point to new KB
  4. Delete old knowledge base
- **Module design**: Document this as a breaking change. Consider using `create_before_destroy` lifecycle on the knowledge base resource.

#### Knowledge Base Storage Configuration Change

- **Behavior**: FORCES REPLACEMENT (`storage_configuration` is `Forces new resource`)
- **Impact**: Same as embedding model change -- complete recreation required
- **This includes**: Changing vector store type (e.g., OpenSearch to Pinecone), changing collection ARN, changing index name

#### Data Source Ingestion Configuration Change

- **Behavior**: FORCES REPLACEMENT (`vector_ingestion_configuration` and all sub-blocks are `Forces new resource`)
- **Impact**: Data source is recreated; sync must be re-triggered
- **This includes**: Changing chunking strategy, chunk size, parsing configuration

#### AgentCore Runtime Updates

- **Container URI change**: In-place update (no replacement)
- **Network mode change**: In-place update
- **Environment variables**: In-place update
- **Authorizer configuration**: In-place update
- **Note**: Runtime endpoints may need to be updated separately if the runtime version changes

---

### 8. Terraform Provider-Specific Edge Cases

#### Timeouts

| Resource | Create | Update | Delete | Notes |
|----------|--------|--------|--------|-------|
| `aws_bedrockagent_agent` | 5m | 5m | 5m | Short; may need increase for complex agents |
| `aws_bedrockagent_agent_action_group` | 30m | 30m | 30m | Long default; schema validation can take time |
| `aws_bedrockagent_agent_alias` | 5m | 5m | 5m | |
| `aws_bedrockagent_knowledge_base` | 30m | 30m | 30m | OpenSearch collection creation can be slow |
| `aws_bedrockagent_data_source` | 30m | N/A | 30m | No update timeout -- some changes force replacement |
| `aws_bedrockagentcore_agent_runtime` | 30m | 30m | 30m | Container pull and startup |
| `aws_bedrockagentcore_gateway` | 30m | 30m | 30m | |
| `aws_bedrockagentcore_memory` | 30m | N/A | 30m | No update timeout listed |
| `aws_bedrockagentcore_browser` | 30m | N/A | 30m | No update timeout listed |

#### skip_resource_in_use_check

Both `aws_bedrockagent_agent` and `aws_bedrockagent_agent_action_group` support `skip_resource_in_use_check`. When `false` (default), deletion will fail if the agent/action group is in use (e.g., active sessions). Set to `true` in module defaults for smoother destroy operations, especially in dev/test environments.

#### Token Vault CMK Singleton

`aws_bedrockagentcore_token_vault_cmk` is a singleton resource -- only one per region. The `token_vault_id` defaults to `"default"`. Deletion only removes it from state, it does NOT modify the actual CMK. This means:
- Multiple Terraform configurations managing the same token vault will conflict
- The module should either manage this as a separate, optional component or document the singleton behavior

#### Write-Only Arguments (Terraform 1.11+)

The AgentCore credential providers (`api_key_credential_provider`, `oauth2_credential_provider`) support write-only arguments (`api_key_wo`, `client_id_wo`, `client_secret_wo`). These require Terraform 1.11+. The module should:
- Default to write-only arguments when possible
- Provide fallback to standard arguments for older Terraform versions
- Document the `*_wo_version` bump pattern for credential rotation

#### Agent Collaboration Requirements

For multi-agent collaboration:
- Supervisor agent must have `agent_collaboration = "SUPERVISOR"` or `"SUPERVISOR_ROUTER"`
- Supervisor agent should set `prepare_agent = false` until collaborators are attached
- Collaborator needs an alias before the supervisor can reference it
- The supervisor's IAM role needs `bedrock:GetAgentAlias` and `bedrock:InvokeAgent` permissions

---

### 9. Recommendations for Module Design

1. **Validation rules**: Add `validation` blocks for instruction length (40-20000 chars), memory event expiry (7-365 days), and naming conventions.

2. **prepare_agent strategy**: Default to `prepare_agent = false` on the agent resource and `true` on the last dependent resource (action group, KB association, or collaborator). Alternatively, expose a `prepare_agent` variable.

3. **Defensive IAM**: Always include `aws_lambda_permission` when creating action groups with Lambda executors. Include KMS key policy grants when encryption is enabled.

4. **Data source sync documentation**: Clearly document that `aws_bedrockagent_data_source` creation does NOT sync data. Provide an example `null_resource` with `local-exec` for triggering sync.

5. **Lifecycle blocks**: Consider `create_before_destroy` on knowledge bases and data sources to minimize downtime during embedding model or chunking strategy changes.

6. **Composite ID outputs**: Export composite IDs for all resources to facilitate state import operations.

7. **skip_resource_in_use_check**: Default to `true` for dev/test friendliness; expose as a variable for production environments.

8. **AgentCore network configuration**: Make network_mode configurable with sensible defaults (PUBLIC for dev, VPC for production). Validate that VPC mode includes security_groups and subnets.

---

### Sources

- AWS Terraform Provider v6.38.0 documentation: `aws_bedrockagent_agent`, `aws_bedrockagent_agent_action_group`, `aws_bedrockagent_agent_alias`, `aws_bedrockagent_agent_knowledge_base_association`, `aws_bedrockagent_knowledge_base`, `aws_bedrockagent_data_source`, `aws_bedrockagent_agent_collaborator`, `aws_bedrockagent_flow`
- AWS Terraform Provider v6.38.0 documentation: `aws_bedrockagentcore_agent_runtime`, `aws_bedrockagentcore_agent_runtime_endpoint`, `aws_bedrockagentcore_gateway`, `aws_bedrockagentcore_gateway_target`, `aws_bedrockagentcore_memory`, `aws_bedrockagentcore_memory_strategy`, `aws_bedrockagentcore_browser`, `aws_bedrockagentcore_code_interpreter`, `aws_bedrockagentcore_api_key_credential_provider`, `aws_bedrockagentcore_oauth2_credential_provider`, `aws_bedrockagentcore_token_vault_cmk`, `aws_bedrockagentcore_workload_identity`
- Public Registry Module: Flaconi/bedrock-agent/aws v1.2.1
- Public Registry Module: CloudPediaAI/ai-agent/aws v1.0.2
- AWS Bedrock Agents quotas: https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html
- AWS Bedrock AgentCore documentation: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/
- AWS Bedrock Agents developer guide: https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html
