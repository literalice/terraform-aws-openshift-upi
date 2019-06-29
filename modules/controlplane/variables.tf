variable "network_context" {
  type    = object({
    cluster_base_domain = string
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
    key_name = string
    subnet_ids = list(string)
    api_target_group_arn = string
    private_api_elb_id = string
  })
}

variable "controlplane_context" {
  type    = object({
    ca_bundle = string
    instance_type = string
    count = number
  })
}

locals {
  cluster_name = var.network_context.cluster_name
  cluster_id = var.network_context.cluster_id
  cluster_tag = var.network_context.cluster_tag
  cluster_base_domain = var.network_context.cluster_base_domain
  cluster_domain = "${local.cluster_name}.${local.cluster_base_domain}"

  vpc_id = var.node_context.vpc_id
  subnet_ids = var.node_context.subnet_ids
  sg_ids = var.node_context.sg_ids
  key_name = var.node_context.key_name
  api_target_group_arn = var.node_context.api_target_group_arn
  private_api_elb_id = var.node_context.private_api_elb_id

  ca_bundle = var.controlplane_context.ca_bundle
  count = var.controlplane_context.count
  instance_type = var.controlplane_context.instance_type
}
