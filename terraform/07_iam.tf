data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_data_access" {
  name = "${var.project_name}-lambda-data-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsDataApi"
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction"
        ]
        Resource = aws_rds_cluster.aurora.arn
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.db_credentials.arn,
          aws_secretsmanager_secret.redshift_credentials.arn
        ]
      },
      {
        Sid    = "DynamoDb"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = [
          aws_dynamodb_table.sessions.arn,
          "${aws_dynamodb_table.sessions.arn}/stream/*"
        ]
      },
      {
        Sid    = "RedshiftDataApi"
        Effect = "Allow"
        Action = [
          "redshift-data:ExecuteStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult"
        ]
        Resource = "*"
      }
    ]
  })
}
