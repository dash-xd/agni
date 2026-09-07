terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

locals {
  nodes = {
    for slot, node in var.nodes : tostring(tonumber(slot)) => node
  }
}

resource "google_compute_instance_from_template" "this" {
  for_each = local.nodes

  name                     = "${var.name_prefix}-${format("%02d", tonumber(each.key))}"
  project                  = var.project
  zone                     = var.zone
  source_instance_template = var.source_instance_template

  metadata = merge(
    var.common_metadata,
    each.value.metadata,
    each.value.user_data == "" ? {} : { "user-data" = each.value.user_data }
  )

  tags = distinct(concat(var.common_tags, each.value.tags))

  network_interface {
    subnetwork = var.subnetwork
    network_ip = var.ipv4_by_slot[each.key]
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  }

  dynamic "service_account" {
    for_each = each.value.service_account_email == "" ? [] : [each.value.service_account_email]
    content {
      email  = service_account.value
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
}
