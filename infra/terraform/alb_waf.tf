resource "aws_lb" "app" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "gateway" {
  name        = "${var.project}-tg-gateway"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"
  health_check { path = "/health" matcher = "200" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action { type = "forward" target_group_arn = aws_lb_target_group.gateway.arn }
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project}-waf"
  scope       = "REGIONAL"
  description = "Basic WAF"
  default_action { allow {} }
  visibility_config { cloudwatch_metrics_enabled = true metric_name = "${var.project}-waf" sampled_requests_enabled = true }
}

resource "aws_wafv2_web_acl_association" "alb_assoc" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

