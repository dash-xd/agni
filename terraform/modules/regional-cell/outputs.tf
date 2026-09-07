output "subnetwork" {
  value = {
    id                  = module.network.id
    self_link           = module.network.self_link
    name                = module.network.name
    ipv4_cidr           = module.network.ipv4_cidr
    usable_ipv4_by_slot = module.network.usable_ipv4_by_slot
  }
}

output "nodes" {
  value = module.nodes.instances
}
