resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_cloudwatch_metric_alarm" "aurora_replica_lag" {
  alarm_name          = "${var.project_name}-aurora-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 1000 # ms
  alarm_description   = "Aurora replica lag exceeded 1s - early warning for failover risk"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "aurora_failover" {
  alarm_name          = "${var.project_name}-aurora-failover-detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Failover"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "An Aurora failover event was detected"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB requests are being throttled"
  dimensions = {
    TableName = aws_dynamodb_table.sessions.name
  }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Aurora Replica Lag (ms)"
          metrics = [["AWS/RDS", "AuroraReplicaLag", "DBClusterIdentifier", aws_rds_cluster.aurora.cluster_identifier]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "DynamoDB Throttled Requests"
          metrics = [["AWS/DynamoDB", "ThrottledRequests", "TableName", aws_dynamodb_table.sessions.name]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "Order API Lambda Errors"
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.order_api.function_name]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "Order API Lambda Duration (ms)"
          metrics = [["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.order_api.function_name]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
        }
      }
    ]
  })
}
