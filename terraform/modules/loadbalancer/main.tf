# ------------------------------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------------------------------
# Public-facing ALB that fronts the EC2 instances in private subnets.
# HTTP only for dev — in prod, add an HTTPS listener with ACM certificate
# and redirect HTTP → HTTPS.
#
# drop_invalid_header_fields = true is an AWS Well-Architected security
# recommendation that prevents HTTP request smuggling attacks.
# ------------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false # dev only — enable in prod

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb"
  })
}

# ------------------------------------------------------------------------------
# Target Group
# ------------------------------------------------------------------------------
# Health check on /health ensures the ALB only routes to instances where
# the application is actually serving. The matcher expects HTTP 200.
#
# deregistration_delay is reduced to 30s for dev — speeds up deployments.
# In prod, keep the default 300s to allow in-flight requests to drain.
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "app" {
  name     = "${var.project}-${var.environment}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-tg"
  })
}

# ------------------------------------------------------------------------------
# Target Group Attachments
# ------------------------------------------------------------------------------
# Registers each EC2 instance with the target group. When instance_count
# increases, new instances are automatically attached.
# ------------------------------------------------------------------------------

resource "aws_lb_target_group_attachment" "app" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = var.instance_ids[count.index]
  port             = var.app_port
}

# ------------------------------------------------------------------------------
# HTTP Listener
# ------------------------------------------------------------------------------
# Default action forwards to the target group. In prod, this should redirect
# to HTTPS (443) and a separate HTTPS listener should handle forwarding.
# ------------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-http-listener"
  })
}
