terraform {
  required_version = ">= 1.3.0"
}

module "network" {
  source = "../regional-network"

  project                  = var.project
  region                   = var.region
  network                  = var.network
  name                     = var.subnetwork_name
  ipv4_cidr                = var.ipv4_cidr
  enable_ipv6              = var.enable_ipv6
  ipv6_access_type         = var.ipv6_access_type
  private_ip_google_access = var.private_ip_google_access
}

module "internal_addresses" {
  source = "../regional-internal-addresses"

  project    = var.project
  region     = var.region
  subnetwork = module.network.self_link
  addresses  = var.internal_addresses
}

module "nodes" {
  source = "../coreos-node"

  project                  = var.project
  zone                     = var.zone
  name_prefix              = var.node_name_prefix
  source_instance_template = var.source_instance_template
  subnetwork               = module.network.self_link
  ipv4_cidr                = var.ipv4_cidr
  enable_ipv6              = var.enable_ipv6
  common_metadata          = var.common_metadata
  common_tags              = var.common_tags
  nodes                    = var.nodes

  depends_on = [module.internal_addresses]
}
