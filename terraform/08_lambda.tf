data "archive_file" "order_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/order_api"
  output_path = "${path.module}/build/order_api.zip"
}

data "archive_file" "etl_sync_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/etl_sync"
  output_path = "${path.module}/build/etl_sync.zip"
}

resource "aws_lambda_function" "order_api" {
  function_name    = "${var.project_name}-order-api"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 15
  memory_size      = 256
  filename         = data.archive_file.order_api_zip.output_path
  source_code_hash = data.archive_file.order_api_zip.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ARN = aws_rds_cluster.aurora.arn
      AURORA_SECRET_ARN  = aws_secretsmanager_secret.db_credentials.arn
      AURORA_DB_NAME     = var.db_name
      SESSIONS_TABLE_NAME = aws_dynamodb_table.sessions.name
    }
  }

  # Note: the RDS Data API and DynamoDB are both reached over the public AWS
  # API endpoints (not inside the VPC), so this Lambda does NOT need VPC
  # config. This is intentional: it avoids Lambda ENI cold-start penalties
  # and is the recommended pattern specifically because the Data API removes
  # the need for Lambda to hold a persistent DB connection inside the VPC.

  tags = {
    Name = "${var.project_name}-order-api"
  }
}

resource "aws_lambda_function" "etl_sync" {
  function_name    = "${var.project_name}-etl-sync"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.etl_sync_zip.output_path
  source_code_hash = data.archive_file.etl_sync_zip.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ARN       = aws_rds_cluster.aurora.arn
      AURORA_SECRET_ARN        = aws_secretsmanager_secret.db_credentials.arn
      AURORA_DB_NAME           = var.db_name
      REDSHIFT_WORKGROUP_NAME  = aws_redshiftserverless_workgroup.analytics.workgroup_name
      REDSHIFT_SECRET_ARN      = aws_secretsmanager_secret.redshift_credentials.arn
      REDSHIFT_DB_NAME         = "analytics"
    }
  }

  tags = {
    Name = "${var.project_name}-etl-sync"
  }
}

# Schedule the ETL sync every 5 minutes
resource "aws_cloudwatch_event_rule" "etl_schedule" {
  name                = "${var.project_name}-etl-schedule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "etl_target" {
  rule      = aws_cloudwatch_event_rule.etl_schedule.name
  target_id = "etl-sync-lambda"
  arn       = aws_lambda_function.etl_sync.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.etl_schedule.arn
}
