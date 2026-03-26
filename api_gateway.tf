#------------------------------------------------------------------------------
# API Gateway Resources (conditional on var.enable_api_gateway)
#
# - HTTP API: lightweight API endpoint for external agent invocation.
# - Default stage: auto-deploy with throttling controls.
#------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# HTTP API
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "this" {
  count = var.enable_api_gateway ? 1 : 0

  name          = "${var.agent_name}-api"
  protocol_type = "HTTP"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Default Stage
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_stage" "this" {
  count = var.enable_api_gateway ? 1 : 0

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }

  tags = local.tags
}
