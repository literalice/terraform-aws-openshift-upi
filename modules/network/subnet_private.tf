# Private subnet: for instances / internal lb

locals {
  private_subnet_count = length(local.availability_zones)
}

resource "aws_subnet" "private" {
  count             = local.private_subnet_count
  vpc_id            = aws_vpc.cluster.id
  availability_zone = element(local.availability_zones, count.index)
  cidr_block        = cidrsubnet(aws_vpc.cluster.cidr_block, ceil(log(local.private_subnet_count + local.public_subnet_count, 2)), count.index)

  tags = merge({
    Name = "${local.cluster_id}-private-${count.index}"
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

resource "aws_eip" "private_nat_gateway" {
  vpc = true

  tags = merge({
    Name = "${local.cluster_id}-private-nat-gateway-ip"
  }, local.cluster_tag)

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_nat_gateway" "private" {
  allocation_id = aws_eip.private_nat_gateway.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge({
    Name = "${local.cluster_id}"
  }, local.cluster_tag)

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.private.id
  }

  tags = merge({
    Name = "${local.cluster_id}-private"
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

# RouteTable to Subnet
resource "aws_route_table_association" "private" {
  count          = local.private_subnet_count
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = aws_route_table.private.id
}
