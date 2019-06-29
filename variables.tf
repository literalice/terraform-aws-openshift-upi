variable "config_dir" {
  description = "openshift-install's config directory"
}

variable "blacklist_az" {
  type = "list"
  description = "Unavailable AZ name list for your AWS account. like: [\"ap-northeast-1a\"]"
}

locals {
  openshift_install_state_path = "${var.config_dir}/.openshift_install_state.json"
}

locals {
  openshift_install_state = jsondecode(file(local.openshift_install_state_path))
}

locals {
  cluster_id = local.openshift_install_state["*installconfig.ClusterID"]["InfraID"]
  cluster_name = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["metadata"]["name"]
  public_key = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["sshKey"]
  cluster_tag = {
    "kubernetes.io/cluster/${local.cluster_id}" = "owned"
  }
  cluster_cidr = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["networking"]["machineCIDR"]
}

locals {
  network_context = {
    cluster_base_domain = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["baseDomain"]
    cluster_name = local.cluster_name
    cluster_id   = local.cluster_id
    cluster_cidr = local.cluster_cidr
    cluster_tag  = local.cluster_tag
    blacklist_az = var.blacklist_az
  }

  bootstrap_node_context = {
    vpc_id = module.network.vpc_id
    subnet_ids = module.network.public_subnet_ids
    sg_ids = [module.network.public_sg_id, module.network.private_sg_id]
    key_name = aws_key_pair.cluster.key_name
    ign_path = "${var.config_dir}/bootstrap.ign"
    api_target_group_arn = module.network.api_target_group_arn
    private_api_elb_id = module.network.private_api_elb_id
  }

  master_node_context = {
    vpc_id = module.network.vpc_id
    subnet_ids = module.network.private_subnet_ids
    sg_ids = [module.network.public_sg_id, module.network.private_sg_id]
    key_name = aws_key_pair.cluster.key_name
    api_target_group_arn = module.network.api_target_group_arn
    private_api_elb_id = module.network.private_api_elb_id
  }

  controlplane_context = {
    count = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["controlPlane"]["replicas"]
    instance_type = local.openshift_install_state["*installconfig.InstallConfig"]["config"]["controlPlane"]["platform"]["aws"]["type"]
    ca_bundle = local.openshift_install_state["*machine.Master"]["Config"]["ignition"]["security"]["tls"]["certificateAuthorities"][0]["source"]
  }

  worker_context = {
    config_dir = var.config_dir
  }
}
