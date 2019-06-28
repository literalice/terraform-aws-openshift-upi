resource "aws_elb" "private_api" {
  name    = "${local.cluster_id}-internal-api"

  internal = true

  subnets = aws_subnet.private[*].id
  security_groups = [aws_security_group.private.id]

  listener {
    instance_port     = 6443
    instance_protocol = "TCP"
    lb_port           = 6443
    lb_protocol       = "TCP"
  }

  listener {
    instance_port     = 22623
    instance_protocol = "TCP"
    lb_port           = 22623
    lb_protocol       = "TCP"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:6443"
    interval            = 10
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = merge({
    Name = "${local.cluster_id}-private-api",
  }, local.cluster_tag)

  lifecycle {
    ignore_changes = ["tags"]
  }
}
