variable "aws_region" { description = "AWS region" type = string default = "us-east-1" }
variable "project"    { description = "Project name prefix" type = string default = "ai-coach" }

variable "vpc_cidr"   { description = "VPC CIDR" type = string default = "10.50.0.0/16" }

variable "ecs_desired_counts" {
  description = "Desired counts for ECS services"
  type = object({ gateway = number, n8n_main = number, n8n_webhook = number, n8n_worker = number })
  default = { gateway = 1, n8n_main = 1, n8n_webhook = 1, n8n_worker = 1 }
}

variable "aurora_capacity" {
  description = "Aurora Serverless v2 ACU range"
  type = object({ min = number, max = number })
  default = { min = 0.5, max = 2 }
}

variable "worker_concurrency" { description = "n8n worker concurrency" type = number default = 5 }

