output "instances" {
  value = {
    for slot, instance in google_compute_instance_from_template.this : slot => {
      id           = instance.id
      name         = instance.name
      self_link    = instance.self_link
      zone         = instance.zone
      internal_ip  = instance.network_interface[0].network_ip
      ipv6_address = try(instance.network_interface[0].ipv6_access_config[0].external_ipv6, null)
    }
  }
}
