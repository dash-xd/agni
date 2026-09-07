output "id" {
  value = google_compute_subnetwork.this.id
}

output "self_link" {
  value = google_compute_subnetwork.this.self_link
}

output "name" {
  value = google_compute_subnetwork.this.name
}

output "ipv4_cidr" {
  value = var.ipv4_cidr
}

output "usable_ipv4_by_slot" {
  description = "Stable slot 0..11 to GCE-usable IPv4 mapping. Host offsets 2..13 avoid GCE's four reserved addresses."
  value = {
    for slot in range(12) : tostring(slot) => cidrhost(var.ipv4_cidr, slot + 2)
  }
}
