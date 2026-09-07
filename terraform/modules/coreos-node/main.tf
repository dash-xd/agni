terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

locals {
  ipv4_prefix        = tonumber(split("/", var.ipv4_cidr)[1])
  usable_ipv4_count  = pow(2, 32 - local.ipv4_prefix) - 4
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
    network_ip = cidrhost(var.ipv4_cidr, tonumber(each.key) + 2)
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  }

  dynamic "service_account" {
    for_each = each.value.service_account_email == "" ? [] : [each.value.service_account_email]
    content {
      email  = service_account.value
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  lifecycle {
    precondition {
      condition     = tonumber(each.key) >= 0 && tonumber(each.key) < local.usable_ipv4_count
      error_message = "node slot ${each.key} is outside the usable address range for ${var.ipv4_cidr}."
    }
  }
}
