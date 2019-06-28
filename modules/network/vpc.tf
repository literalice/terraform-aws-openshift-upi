resource "aws_vpc" "cluster" {
  cidr_block                       = local.cluster_cidr
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = merge({
    Name = local.cluster_id
  }, local.cluster_tag)

  lifecycle {
    # ignore_changes = ["tags.%", "tags.openshift_creationDate", "tags.openshift_expirationDate"]
    ignore_changes = ["tags"]
  }
}

