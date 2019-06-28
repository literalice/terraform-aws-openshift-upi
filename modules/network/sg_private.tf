resource "aws_security_group" "private" {
  name        = "${local.cluster_id}-private"
  description = "Cluster private group for ${local.cluster_id}"

  vpc_id = aws_vpc.cluster.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge({
    Name = "${local.cluster_id}-private",
  }, local.cluster_tag)

  lifecycle {
    ignore_changes = ["tags"]
  }
}
