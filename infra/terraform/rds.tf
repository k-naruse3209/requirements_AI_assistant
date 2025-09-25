resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project}-db-subnet"
  subnet_ids = aws_subnet.private_db[*].id
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project}-aurora"
  engine             = "aurora-mysql"
  engine_mode        = "provisioned"
  database_name      = "ai_coach"
  master_username    = "admin"
  master_password    = "Admin123456!" # replace via Secrets Manager in production
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  storage_encrypted  = true
  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_capacity.min
    max_capacity = var.aurora_capacity.max
  }
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count               = 2
  identifier          = "${var.project}-aurora-${count.index}"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora.engine
}

