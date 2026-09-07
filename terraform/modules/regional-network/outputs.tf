locals {
  ipv4_prefix       = tonumber(split("/", var.ipv4_cidr)[1])
  ipv4_address_count = pow(2, 32 - local.ipv4_prefix)
  usable_ipv4_count = local.ipv4_address_count - 4
}

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

output "usable_ipv4_count" {
  description = "Number of VM-usable IPv4 addresses after Google Cloud's four reserved subnet addresses."
  value       = local.usable_ipv4_count
}

output "first_usable_ipv4" {
  value = cidrhost(var.ipv4_cidr, 2)
}

output "last_usable_ipv4" {
  value = cidrhost(var.ipv4_cidr, local.ipv4_address_count - 3)
}
