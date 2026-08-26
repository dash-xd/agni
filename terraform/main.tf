terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.3.0"

  backend "gcs" {}
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  instance_name = "${var.instance_name_prefix}-${random_id.suffix.hex}"
  internal_ip   = cidrhost(var.subnetwork_ipv4_cidr, var.vm_slot + 2)
}

resource "google_compute_subnetwork" "coreos" {
  name                     = var.subnetwork_name
  project                  = var.project
  region                   = var.region
  network                  = var.network
  ip_cidr_range            = var.subnetwork_ipv4_cidr
  private_ip_google_access = true

  stack_type       = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  ipv6_access_type = var.enable_ipv6 ? var.ipv6_access_type : null
}

resource "google_compute_instance_from_template" "vm" {
  name                     = local.instance_name
  zone                     = var.zone
  source_instance_template = "projects/${var.project}/${var.region}/instanceTemplates/${var.template_name}"
  project                  = var.project

  metadata = {
    ssh-keys  = "core:${file(var.ssh_public_key_file)}"
    user-data = file("${path.module}/config.ign")
  }

  tags = distinct(concat(["squid-client"], var.network_tags))

  network_interface {
    subnetwork = google_compute_subnetwork.coreos.id
    network_ip = local.internal_ip
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"

    dynamic "ipv6_access_config" {
      for_each = var.enable_ipv6 && var.ipv6_access_type == "EXTERNAL" ? [1] : []
      content {
        network_tier = "PREMIUM"
      }
    }
  }

  dynamic "service_account" {
    for_each = var.service_account_email != "" ? [1] : []
    content {
      email  = var.service_account_email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
}
