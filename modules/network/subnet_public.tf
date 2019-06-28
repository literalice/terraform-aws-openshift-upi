# Public subnet: for router / master public LB

locals {
  public_subnet_count = "${length(local.availability_zones)}"
}

resource "aws_subnet" "public" {
  count                   = local.public_subnet_count
  availability_zone       = local.availability_zones[count.index]
  vpc_id                  = aws_vpc.cluster.id
  cidr_block              = cidrsubnet(aws_vpc.cluster.cidr_block, ceil(log(local.private_subnet_count + local.public_subnet_count, 2)), local.private_subnet_count + count.index)
  map_public_ip_on_launch = true

  tags = merge({
    Name = "${local.cluster_id}-public-${count.index}"
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

# Public access to the router
resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.cluster.id

  tags = merge({
    Name = local.cluster_id
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

# Public route table: attach Internet gw for internet access.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cluster.id

  tags = merge({
    Name = "${local.cluster_id}-public-rt"
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.public.id
  depends_on             = ["aws_route_table.public"]
}

resource "aws_route_table_association" "public" {
  count          = local.public_subnet_count
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}
