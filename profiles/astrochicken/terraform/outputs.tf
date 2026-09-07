output "subnetwork" {
  value = module.region.subnetwork
}

output "nodes" {
  value = module.region.nodes
}

output "service_addresses" {
  value = module.region.internal_addresses
}

output "shadow_functions" {
  value = {
    gen1 = { for name, fn in module.gen1_functions : name => fn.uri }
    gen2 = { for name, fn in module.gen2_functions : name => fn.uri }
  }
}
