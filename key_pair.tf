resource "aws_key_pair" "cluster" {
  key_name   = local.cluster_id
  public_key = local.public_key
}
