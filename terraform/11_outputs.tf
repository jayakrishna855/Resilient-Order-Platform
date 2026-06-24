output "api_endpoint" {
  description = "Base URL for the order API"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "aurora_cluster_id" {
  description = "Aurora cluster identifier (used for failover testing)"
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "aurora_cluster_arn" {
  value = aws_rds_cluster.aurora.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "redshift_workgroup_name" {
  value = aws_redshiftserverless_workgroup.analytics.workgroup_name
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
