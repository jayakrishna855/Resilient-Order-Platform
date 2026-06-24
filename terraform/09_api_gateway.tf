resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "order_api" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.order_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_order" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /order"
  target    = "integrations/${aws_apigatewayv2_integration.order_api.id}"
}

resource "aws_apigatewayv2_route" "get_order" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /order/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.order_api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 7
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
