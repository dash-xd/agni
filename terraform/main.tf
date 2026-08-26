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
    network    = var.subnetwork == "" ? var.network : null
    subnetwork = var.subnetwork != "" ? var.subnetwork : null
    network_ip = var.internal_ip != "" ? var.internal_ip : null
  }

  dynamic "service_account" {
    for_each = var.service_account_email != "" ? [1] : []
    content {
      email  = var.service_account_email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
}
