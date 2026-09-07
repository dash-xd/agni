output "subnetwork" {
  value = {
    id                  = module.network.id
    self_link           = module.network.self_link
    name                = module.network.name
    ipv4_cidr           = module.network.ipv4_cidr
    usable_ipv4_count   = module.network.usable_ipv4_count
    first_usable_ipv4   = module.network.first_usable_ipv4
    last_usable_ipv4    = module.network.last_usable_ipv4
  }
}

output "nodes" {
  value = module.nodes.instances
}
