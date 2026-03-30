# terraform-aws-bedrock-agentcore

Terraform module for deploying [Amazon Bedrock Agents](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html) with secure defaults, optional knowledge bases (RAG), guardrails, action groups, API Gateway exposure, and conversation memory.

## Features

- **Bedrock Agent** with configurable foundation model and instruction prompt
- **KMS encryption** at rest (module-created key or bring your own)
- **CloudWatch logging** with configurable retention
- **Code interpreter** sandbox for Python execution (enabled by default)
- **Knowledge base** with S3 data source and OpenSearch Serverless vector store
- **Action groups** with Lambda-backed tools and OpenAPI schema support
- **Guardrails** with content filters, topic denials, and PII protection
- **Conversation memory** with session summaries and configurable retention
- **API Gateway** (HTTP API) with IAM authorization and throttling
- **Least-privilege IAM** roles scoped to the specific agent and resources

## Usage

### Basic

```hcl
module "bedrock_agent" {
  source  = "app.terraform.io/hashi-demos-apj/bedrock-agentcore/aws"
  version = "~> 0.2"

  agent_name          = "basic-assistant"
  foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  agent_instruction   = "You are a helpful assistant that answers questions about cloud infrastructure. Be concise and accurate in your responses."
  environment         = "dev"
  owner               = "platform-team"
  cost_center         = "CC-1234"
}
```

This creates an agent with secure defaults: KMS encryption, CloudWatch logging (90-day retention), code interpreter enabled, no public endpoint, and least-privilege IAM.

### With Knowledge Base and Guardrails

```hcl
module "bedrock_agent" {
  source  = "app.terraform.io/hashi-demos-apj/bedrock-agentcore/aws"
  version = "~> 0.2"

  agent_name          = "enterprise-assistant"
  foundation_model_id = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  agent_instruction   = "You are an enterprise assistant. Always cite sources from the knowledge base."
  environment         = "prod"
  owner               = "ml-platform-team"
  cost_center         = "CC-5678"

  # Knowledge base (RAG)
  enable_knowledge_base        = true
  knowledge_base_s3_bucket_arn = "arn:aws:s3:::my-company-docs"
  opensearch_collection_arn    = "arn:aws:aoss:us-east-1:123456789012:collection/abc123"
  knowledge_base_description   = "Company policies and technical documentation"

  # Guardrail
  guardrail_config = {
    name = "enterprise-guardrail"
    content_filters = [
      { type = "HATE",      input_strength = "HIGH", output_strength = "HIGH" },
      { type = "VIOLENCE",  input_strength = "HIGH", output_strength = "HIGH" },
    ]
    pii_filters = [
      { type = "US_SOCIAL_SECURITY_NUMBER", action = "BLOCK" },
      { type = "EMAIL",                     action = "ANONYMIZE" },
    ]
  }

  # API Gateway
  enable_api_gateway       = true
  api_throttle_rate_limit  = 200
  api_throttle_burst_limit = 100

  # Memory
  enable_memory       = true
  memory_storage_days = 14

  log_retention_days = 365
}
```

See the [examples/](examples/) directory for complete working configurations.

## Prerequisites

- Terraform >= 1.7
- AWS Provider >= 6.0
- [Foundation model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) enabled in the target AWS account
- For knowledge bases: an existing OpenSearch Serverless collection and S3 bucket
- For action groups: deployed Lambda functions

## Security

This module applies secure defaults that can be customized but not disabled:

| Control | Default | Configurable |
|---------|---------|-------------|
| Encryption at rest | Module-created KMS key | BYO via `kms_key_arn` |
| Logging | CloudWatch, 90-day retention | `log_retention_days` |
| IAM | Least-privilege, scoped to agent | Automatic |
| API Gateway auth | IAM authorization | Always-on when enabled |
| API throttling | 100 rps / 50 burst | `api_throttle_rate_limit`, `api_throttle_burst_limit` |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.38.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_apigatewayv2_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_stage.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_bedrock_guardrail.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_guardrail) | resource |
| [aws_bedrock_guardrail_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_guardrail_version) | resource |
| [aws_bedrockagent_agent.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent) | resource |
| [aws_bedrockagent_agent_action_group.code_interpreter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_action_group) | resource |
| [aws_bedrockagent_agent_action_group.custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_action_group) | resource |
| [aws_bedrockagent_agent_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_alias) | resource |
| [aws_bedrockagent_agent_knowledge_base_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_knowledge_base_association) | resource |
| [aws_bedrockagent_data_source.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_data_source) | resource |
| [aws_bedrockagent_knowledge_base.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_knowledge_base) | resource |
| [aws_cloudwatch_log_group.api_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.knowledge_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.knowledge_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_lambda_permission.action_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.agent_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.agent_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_key_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.knowledge_base_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.knowledge_base_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_action_group_definitions"></a> [action\_group\_definitions](#input\_action\_group\_definitions) | List of action group definitions. Each must specify either lambda\_arn or custom\_control for execution, and optionally api\_schema or function\_schema for the API contract. | <pre>list(object({<br/>    name                 = string<br/>    description          = optional(string, "")<br/>    lambda_arn           = optional(string)<br/>    custom_control       = optional(string)<br/>    api_schema_payload   = optional(string)<br/>    api_schema_s3_bucket = optional(string)<br/>    api_schema_s3_key    = optional(string)<br/>    function_schema      = optional(any)<br/>  }))</pre> | `[]` | no |
| <a name="input_agent_instruction"></a> [agent\_instruction](#input\_agent\_instruction) | Instruction prompt defining agent behavior. Must be 40-20000 characters. | `string` | n/a | yes |
| <a name="input_agent_name"></a> [agent\_name](#input\_agent\_name) | Name of the Bedrock Agent. Alphanumeric, hyphens, and underscores only. | `string` | n/a | yes |
| <a name="input_api_throttle_burst_limit"></a> [api\_throttle\_burst\_limit](#input\_api\_throttle\_burst\_limit) | API Gateway burst request limit (concurrent requests). | `number` | `50` | no |
| <a name="input_api_throttle_rate_limit"></a> [api\_throttle\_rate\_limit](#input\_api\_throttle\_rate\_limit) | API Gateway steady-state request rate limit (requests per second). | `number` | `100` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | Cost center code for billing attribution. Used in CostCenter tag. | `string` | n/a | yes |
| <a name="input_enable_api_gateway"></a> [enable\_api\_gateway](#input\_enable\_api\_gateway) | Enable an HTTP API Gateway endpoint for external agent invocation with IAM authorization. | `bool` | `false` | no |
| <a name="input_enable_code_interpreter"></a> [enable\_code\_interpreter](#input\_enable\_code\_interpreter) | Enable the code interpreter sandbox for Python code execution. | `bool` | `true` | no |
| <a name="input_enable_knowledge_base"></a> [enable\_knowledge\_base](#input\_enable\_knowledge\_base) | Enable knowledge base for retrieval-augmented generation. Requires opensearch\_collection\_arn and knowledge\_base\_s3\_bucket\_arn. | `bool` | `false` | no |
| <a name="input_enable_memory"></a> [enable\_memory](#input\_enable\_memory) | Enable conversation memory with session summaries for context persistence across sessions. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment name. Must be one of: dev, staging, prod. | `string` | n/a | yes |
| <a name="input_foundation_model_id"></a> [foundation\_model\_id](#input\_foundation\_model\_id) | Foundation model identifier (e.g., "anthropic.claude-3-5-sonnet-20241022-v2:0"). Model access must be enabled in the account. | `string` | n/a | yes |
| <a name="input_guardrail_config"></a> [guardrail\_config](#input\_guardrail\_config) | Configuration to create a new guardrail. Mutually exclusive with guardrail\_id. | <pre>object({<br/>    name                      = string<br/>    blocked_input_messaging   = optional(string, "Sorry, I cannot process that request.")<br/>    blocked_outputs_messaging = optional(string, "Sorry, I cannot provide that response.")<br/>    content_filters = optional(list(object({<br/>      type            = string<br/>      input_strength  = optional(string, "HIGH")<br/>      output_strength = optional(string, "HIGH")<br/>    })), [])<br/>    topic_denials = optional(list(object({<br/>      name       = string<br/>      definition = string<br/>      examples   = optional(list(string), [])<br/>    })), [])<br/>    pii_filters = optional(list(object({<br/>      type   = string<br/>      action = optional(string, "BLOCK")<br/>    })), [])<br/>  })</pre> | `null` | no |
| <a name="input_guardrail_id"></a> [guardrail\_id](#input\_guardrail\_id) | ID of an existing Bedrock Guardrail to associate with the agent. Mutually exclusive with guardrail\_config. | `string` | `null` | no |
| <a name="input_guardrail_version"></a> [guardrail\_version](#input\_guardrail\_version) | Version number of the existing guardrail. Required when guardrail\_id is provided. | `string` | `null` | no |
| <a name="input_idle_session_ttl"></a> [idle\_session\_ttl](#input\_idle\_session\_ttl) | Idle session timeout in seconds. Agent sessions are terminated after this period of inactivity. Increase for long-running analytical or multi-step agent workflows. | `number` | `600` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of an existing KMS key for encryption at rest. If null, the module creates a KMS key with proper Bedrock service grants. | `string` | `null` | no |
| <a name="input_knowledge_base_description"></a> [knowledge\_base\_description](#input\_knowledge\_base\_description) | Description of the knowledge base purpose. The agent uses this description to decide when to query the knowledge base. | `string` | `"Knowledge base for agent context"` | no |
| <a name="input_knowledge_base_embedding_model"></a> [knowledge\_base\_embedding\_model](#input\_knowledge\_base\_embedding\_model) | Embedding model for knowledge base vector generation. | `string` | `"amazon.titan-embed-text-v2:0"` | no |
| <a name="input_knowledge_base_s3_bucket_arn"></a> [knowledge\_base\_s3\_bucket\_arn](#input\_knowledge\_base\_s3\_bucket\_arn) | ARN of the S3 bucket containing knowledge base source documents. Required when enable\_knowledge\_base is true. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log group retention period in days. Must be a valid CloudWatch retention value. | `number` | `90` | no |
| <a name="input_memory_storage_days"></a> [memory\_storage\_days](#input\_memory\_storage\_days) | Number of days to retain conversation memory. Only used when memory is enabled. | `number` | `30` | no |
| <a name="input_opensearch_collection_arn"></a> [opensearch\_collection\_arn](#input\_opensearch\_collection\_arn) | ARN of the OpenSearch Serverless collection for knowledge base vector storage. Required when enable\_knowledge\_base is true. | `string` | `null` | no |
| <a name="input_opensearch_vector_index_name"></a> [opensearch\_vector\_index\_name](#input\_opensearch\_vector\_index\_name) | Name of the vector index in the OpenSearch Serverless collection. | `string` | `"bedrock-knowledge-base-default-index"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team or individual responsible for this agent. Used in Owner tag. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all taggable resources. Merged with required tags; consumer tags take precedence. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_agent_alias_arn"></a> [agent\_alias\_arn](#output\_agent\_alias\_arn) | Full ARN of the agent alias |
| <a name="output_agent_alias_id"></a> [agent\_alias\_id](#output\_agent\_alias\_id) | Identifier of the agent alias used for invocation |
| <a name="output_agent_arn"></a> [agent\_arn](#output\_agent\_arn) | Full ARN of the Bedrock Agent |
| <a name="output_agent_id"></a> [agent\_id](#output\_agent\_id) | Unique identifier of the Bedrock Agent. |
| <a name="output_agent_role_arn"></a> [agent\_role\_arn](#output\_agent\_role\_arn) | ARN of the IAM role used by the agent |
| <a name="output_api_endpoint"></a> [api\_endpoint](#output\_api\_endpoint) | HTTP API Gateway endpoint URL (null when disabled) |
| <a name="output_guardrail_id"></a> [guardrail\_id](#output\_guardrail\_id) | ID of the module-created guardrail (null when using BYO or no guardrail) |
| <a name="output_guardrail_version"></a> [guardrail\_version](#output\_guardrail\_version) | Version number of the module-created guardrail (null when using BYO or no guardrail) |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key used for encryption (module-created or BYO) |
| <a name="output_knowledge_base_arn"></a> [knowledge\_base\_arn](#output\_knowledge\_base\_arn) | ARN of the knowledge base (null when disabled) |
| <a name="output_knowledge_base_id"></a> [knowledge\_base\_id](#output\_knowledge\_base\_id) | Identifier of the knowledge base (null when disabled) |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the CloudWatch log group |
<!-- END_TF_DOCS -->

## License

This project is licensed under the [Apache License 2.0](LICENSE).
