resource "aws_lb" "api" {
  name                             = "${local.cluster_id}-api"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = aws_subnet.public[*].id
  enable_cross_zone_load_balancing = true

  tags = merge({
    Name = "${local.cluster_id}-api",
  }, local.cluster_tag)

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_lb_target_group" "api" {
  name                 = "${local.cluster_id}-api"
  port                 = 6443
  protocol             = "TCP"
  vpc_id               = aws_vpc.cluster.id
  deregistration_delay = 180

  health_check {
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.api.arn
    type             = "forward"
  }
}
