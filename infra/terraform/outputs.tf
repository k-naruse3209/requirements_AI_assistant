output "alb_url" {
  description = "ALB DNS name"
  value       = aws_lb.app.dns_name
}

output "db_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "secrets_arns" {
  description = "Secrets Manager ARNs"
  value       = {
    symanto = aws_secretsmanager_secret.symanto.arn
    openai  = aws_secretsmanager_secret.openai.arn
    db      = aws_secretsmanager_secret.db.arn
  }
}

