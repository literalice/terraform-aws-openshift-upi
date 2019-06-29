data "aws_region" "current" {}

variable "network_context" {
  type    = object({
    cluster_base_domain = string
    cluster_name = string
    cluster_id = string
    cluster_tag = map(string)
    blacklist_az = list(string)
  })
}

variable "worker_context" {
  type    = object({
    config_dir = string
  })
}

locals {
  cluster_id = var.network_context.cluster_id
  cluster_name = var.network_context.cluster_name
  cluster_tag = var.network_context.cluster_tag
  cluster_base_domain = var.network_context.cluster_base_domain
  cluster_domain = "${local.cluster_name}.${local.cluster_base_domain}"
  blacklist_az = var.network_context.blacklist_az
  config_dir = var.worker_context.config_dir
}
