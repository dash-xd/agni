terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "google_compute_address" "this" {
  for_each = var.addresses

  project      = var.project
  region       = var.region
  name         = each.value.name
  description  = each.value.description
  address_type = "INTERNAL"
  subnetwork   = var.subnetwork
  address      = each.value.address
}
