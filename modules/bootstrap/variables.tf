variable "network_context" {
  type    = object({
    cluster_name = string
    cluster_id = string
    cluster_cidr = string
    cluster_tag = map(string)
  })
}

variable "node_context" {
  type    = object({
    vpc_id = string
    sg_ids = list(string)
    ign_path = string
    key_name = string
    subnet_ids = list(string)
    api_target_group_arn = string
    private_api_elb_id = string
  })
}

locals {
  cluster_name = var.network_context.cluster_name
  cluster_id = var.network_context.cluster_id
  cluster_tag = var.network_context.cluster_tag

  vpc_id = var.node_context.vpc_id
  subnet_ids = var.node_context.subnet_ids
  sg_ids = var.node_context.sg_ids
  target_groups = var.node_context.target_groups
  key_name = var.node_context.key_name
  ign_path = var.node_context.ign_path
  api_target_group_arn = var.node_context.api_target_group_arn
  private_api_elb_id = var.node_context.private_api_elb_id
}
