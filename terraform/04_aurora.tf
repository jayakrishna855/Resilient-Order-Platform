resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-aurora-subnet-group"
  }
}

resource "random_password" "db_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}-aurora-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master_password.result
  })
}

# Aurora PostgreSQL Serverless v2 cluster, Multi-AZ (2 instances across AZs)
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.project_name}-aurora"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "15.4"
  database_name           = var.db_name
  master_username         = var.db_master_username
  master_password         = random_password.db_master_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora_sg.id]
  storage_encrypted       = true
  skip_final_snapshot     = true
  backup_retention_period = 1
  enable_http_endpoint    = true # RDS Data API - lets Lambda talk to Aurora without managing DB connections/VPC ENIs

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4
  }

  tags = {
    Name = "${var.project_name}-aurora-cluster"
  }
}

# Writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-aurora-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  availability_zone  = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-aurora-writer"
  }
}

# Reader instance in a second AZ -> this is what gives Multi-AZ fault tolerance / automated failover
resource "aws_rds_cluster_instance" "reader" {
  identifier         = "${var.project_name}-aurora-reader"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  availability_zone  = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-aurora-reader"
  }
}
