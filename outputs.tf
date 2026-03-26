output "agent_id" {
  description = "Unique identifier of the Bedrock Agent"
  value       = aws_bedrockagent_agent.this.agent_id
}

output "agent_arn" {
  description = "Full ARN of the Bedrock Agent"
  value       = aws_bedrockagent_agent.this.agent_arn
}

output "agent_alias_id" {
  description = "Identifier of the agent alias used for invocation"
  value       = aws_bedrockagent_agent_alias.this.agent_alias_id
}

output "agent_alias_arn" {
  description = "Full ARN of the agent alias"
  value       = aws_bedrockagent_agent_alias.this.agent_alias_arn
}

output "agent_role_arn" {
  description = "ARN of the IAM role used by the agent"
  value       = aws_iam_role.agent.arn
}

output "knowledge_base_id" {
  description = "Identifier of the knowledge base (null when disabled)"
  value       = try(aws_bedrockagent_knowledge_base.this[0].id, null)
}

output "knowledge_base_arn" {
  description = "ARN of the knowledge base (null when disabled)"
  value       = try(aws_bedrockagent_knowledge_base.this[0].arn, null)
}

output "api_endpoint" {
  description = "HTTP API Gateway endpoint URL (null when disabled)"
  value       = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (module-created or BYO)"
  value       = local.effective_kms_key_arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "guardrail_id" {
  description = "ID of the module-created guardrail (null when using BYO or no guardrail)"
  value       = try(aws_bedrock_guardrail.this[0].guardrail_id, null)
}

output "guardrail_version" {
  description = "Version number of the module-created guardrail (null when using BYO or no guardrail)"
  value       = try(tostring(aws_bedrock_guardrail_version.this[0].version), null)
}
