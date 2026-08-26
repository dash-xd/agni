output "subnetwork_name" {
  value = google_compute_subnetwork.coreos.name
}

output "subnetwork_ipv4_cidr" {
  value = google_compute_subnetwork.coreos.ip_cidr_range
}

output "subnetwork_ipv6_prefix" {
  value = var.enable_ipv6 ? coalesce(
    try(google_compute_subnetwork.coreos.external_ipv6_prefix, null),
    try(google_compute_subnetwork.coreos.internal_ipv6_prefix, null)
  ) : null
}

output "leader" {
  value = {
    slot        = var.leader_slot
    name        = google_compute_instance_from_template.vm[tostring(var.leader_slot)].name
    instance_id = google_compute_instance_from_template.vm[tostring(var.leader_slot)].instance_id
    internal_ip = local.leader_ip
    public_ipv4 = var.allocate_leader_public_ipv4 ? google_compute_address.leader[0].address : null
  }
}

output "instances" {
  value = {
    for slot, vm in google_compute_instance_from_template.vm : slot => {
      name        = vm.name
      instance_id = vm.instance_id
      zone        = vm.zone
      internal_ip = vm.network_interface[0].network_ip
      ipv6        = try(vm.network_interface[0].ipv6_access_config[0].external_ipv6, null)
      role        = tonumber(slot) == var.leader_slot ? "leader" : "member"
      redis_db    = tonumber(slot)
    }
  }
}

output "uncoupled_redis_databases" {
  value = [12, 13, 14, 15]
}
