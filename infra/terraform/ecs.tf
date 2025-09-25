resource "aws_ecs_cluster" "this" {
  name = "${var.project}-ecs"
}

resource "aws_iam_role" "task_execution" {
  name = "${var.project}-ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals { 
  gateway_image    = "nginxdemos/hello:latest" # placeholder; replace with real image that serves /health
  n8n_image        = "n8nio/n8n:latest"
}

resource "aws_ecs_task_definition" "gateway" {
  family                   = "${var.project}-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions    = jsonencode([
    {
      name  = "gateway",
      image = local.gateway_image,
      portMappings = [{ containerPort = 8000, protocol = "tcp" }],
      essential = true,
      command = ["/bin/sh","-c","python -m http.server 8000 & echo ok > /health && tail -f /dev/null"],
      healthCheck = { command = ["CMD-SHELL","curl -f http://localhost:8000/health || exit 1"], interval=30, timeout=5, retries=3, startPeriod=5 }
    }
  ])
  runtime_platform { operating_system_family = "LINUX" cpu_architecture = "X86_64" }
}

resource "aws_ecs_service" "gateway" {
  name            = "${var.project}-gateway"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = var.ecs_desired_counts.gateway
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = false
    subnets         = aws_subnet.private_app[*].id
    security_groups = [aws_security_group.ecs_sg.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "gateway"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener.http]
}

# Minimal placeholders for n8n services
resource "aws_ecs_task_definition" "n8n" {
  family                   = "${var.project}-n8n"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  container_definitions    = jsonencode([
    { name = "n8n", image = local.n8n_image, essential = true, portMappings = [{containerPort=5678}] }
  ])
  runtime_platform { operating_system_family = "LINUX" cpu_architecture = "X86_64" }
}

resource "aws_ecs_service" "n8n_main" {
  name            = "${var.project}-n8n-main"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.n8n.arn
  desired_count   = var.ecs_desired_counts.n8n_main
  launch_type     = "FARGATE"
  network_configuration { assign_public_ip = false subnets = aws_subnet.private_app[*].id security_groups=[aws_security_group.ecs_sg.id] }
}

resource "aws_ecs_service" "n8n_webhook" {
  name            = "${var.project}-n8n-webhook"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.n8n.arn
  desired_count   = var.ecs_desired_counts.n8n_webhook
  launch_type     = "FARGATE"
  network_configuration { assign_public_ip = false subnets = aws_subnet.private_app[*].id security_groups=[aws_security_group.ecs_sg.id] }
}

resource "aws_ecs_service" "n8n_worker" {
  name            = "${var.project}-n8n-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.n8n.arn
  desired_count   = var.ecs_desired_counts.n8n_worker
  launch_type     = "FARGATE"
  network_configuration { assign_public_ip = false subnets = aws_subnet.private_app[*].id security_groups=[aws_security_group.ecs_sg.id] }
}

