resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project}-redis-subnet"
  subnet_ids = aws_subnet.private_app[*].id
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${var.project}-redis"
  description                   = "Redis for queue/rate-limit"
  engine                        = "redis"
  node_type                     = "cache.t4g.small"
  automatic_failover_enabled    = true
  multi_az_enabled              = true
  num_node_groups               = 1
  replicas_per_node_group       = 1
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis_sg.id]
}

