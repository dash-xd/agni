output "leader_name" {
  value = google_compute_instance_from_template.leader.name
}

output "leader_internal_ip" {
  value = local.leader_ip
}

output "leader_public_ipv4" {
  value = google_compute_address.leader.address
}

output "hostname" {
  value = var.cloudflare_hostname
}

output "member_source_ranges" {
  value = var.member_source_ranges
}
