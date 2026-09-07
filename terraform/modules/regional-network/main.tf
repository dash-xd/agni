terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "google_compute_subnetwork" "this" {
  name                     = var.name
  project                  = var.project
  region                   = var.region
  network                  = var.network
  ip_cidr_range            = var.ipv4_cidr
  private_ip_google_access = var.private_ip_google_access
  stack_type               = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  ipv6_access_type         = var.enable_ipv6 ? var.ipv6_access_type : null
}
