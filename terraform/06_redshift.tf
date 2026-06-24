resource "aws_redshiftserverless_namespace" "analytics" {
  namespace_name      = "${var.project_name}-analytics"
  admin_username       = "analytics_admin"
  admin_user_password  = random_password.redshift_password.result
  db_name              = "analytics"
}

resource "random_password" "redshift_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "redshift_credentials" {
  name = "${var.project_name}-redshift-credentials"
}

resource "aws_secretsmanager_secret_version" "redshift_credentials" {
  secret_id = aws_secretsmanager_secret.redshift_credentials.id
  secret_string = jsonencode({
    username = "analytics_admin"
    password = random_password.redshift_password.result
  })
}

resource "aws_security_group" "redshift_sg" {
  name        = "${var.project_name}-redshift-sg"
  description = "Security group for Redshift Serverless workgroup"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redshift from Lambda"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redshift-sg"
  }
}

resource "aws_redshiftserverless_workgroup" "analytics" {
  namespace_name     = aws_redshiftserverless_namespace.analytics.namespace_name
  workgroup_name     = "${var.project_name}-analytics-wg"
  base_capacity      = 8 # RPUs, smallest supported increment for serverless
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.redshift_sg.id]
  publicly_accessible = false
}
