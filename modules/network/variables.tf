variable "context" {
  type    = object({
    cluster_base_domain = string
    cluster_name = string
    cluster_id = string
    cluster_cidr = string
    cluster_tag = map(string)
    blacklist_az = list(string)
  })
}

locals {
  cluster_base_domain = var.context.cluster_base_domain
  cluster_domain = "${var.context.cluster_name}.${var.context.cluster_base_domain}"
  cluster_name = var.context.cluster_name
  cluster_id = var.context.cluster_id
  cluster_cidr = var.context.cluster_cidr
  cluster_tag = var.context.cluster_tag
  blacklist_az = var.context.blacklist_az
}
