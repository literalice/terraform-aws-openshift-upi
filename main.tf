module "network" {
  source = "./modules/network"
  context = local.network_context
}

module "bootstrap" {
  source = "./modules/bootstrap"
  network_context = local.network_context
  node_context = local.bootstrap_node_context
}

module "controlplane" {
  source = "./modules/controlplane"
  network_context = local.network_context
  node_context = local.master_node_context
  controlplane_context = local.controlplane_context
}

module "worker" {
  source = "./modules/worker"
  network_context = local.network_context
  worker_context = local.worker_context
}
