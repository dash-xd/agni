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

data "terraform_remote_state" "leader" {
  backend = "gcs"

  config = {
    bucket = var.leader_state_bucket
    prefix = var.leader_state_prefix
  }
}

locals {
  slots           = { for slot in var.vm_slots : tostring(slot) => slot }
  egress_proxy_ip = data.terraform_remote_state.leader.outputs.leader_internal_ip
}

resource "random_id" "suffix" {
  for_each    = local.slots
  byte_length = 4

  keepers = {
    deployment_metadata = jsonencode(merge(
      var.member_metadata,
      lookup(var.member_metadata_by_slot, each.key, {})
    ))
  }
}

resource "google_compute_subnetwork" "coreos" {
  name                     = var.subnetwork_name
  project                  = var.project
  region                   = var.region
  network                  = var.network
  ip_cidr_range            = var.subnetwork_ipv4_cidr
  private_ip_google_access = true
  stack_type               = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  ipv6_access_type         = var.enable_ipv6 ? var.ipv6_access_type : null
}

resource "google_compute_instance_from_template" "vm" {
  for_each = local.slots

  name                     = "${var.instance_name_prefix}-${format("%02d", each.value)}-${random_id.suffix[each.key].hex}"
  zone                     = var.zone
  source_instance_template = "projects/${var.project}/${var.region}/instanceTemplates/${var.template_name}"
  project                  = var.project

  metadata = merge(
    var.member_metadata,
    lookup(var.member_metadata_by_slot, each.key, {}),
    {
      ssh-keys                    = "core:${file(var.ssh_public_key_file)}"
      user-data                   = file("${path.module}/config.ign")
      agni-role                   = "member"
      agni-leader-ip              = local.egress_proxy_ip
      agni-member-ips             = ""
      agni-subnet-cidr            = var.subnetwork_ipv4_cidr
      agni-nginx-upstream-port    = tostring(var.member_service_port)
      agni-redis-db               = tostring(each.value)
      agni-cloudflare-https       = "false"
      agni-cloudflare-hostname    = ""
      agni-origin-certificate-b64 = ""
      agni-origin-private-key-b64 = ""
    }
  )

  tags = distinct(concat([
    "squid-client",
    "agni-member",
    "redis-db-${each.value}",
  ], var.network_tags))

  network_interface {
    subnetwork = google_compute_subnetwork.coreos.id
    network_ip = cidrhost(var.subnetwork_ipv4_cidr, each.value + 2)
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  }

  dynamic "service_account" {
    for_each = var.service_account_email != "" ? [1] : []
    content {
      email  = var.service_account_email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
}

resource "google_compute_firewall" "leader_to_members" {
  name        = "${var.subnetwork_name}-leader-to-members"
  project     = var.project
  network     = var.network
  direction   = "INGRESS"
  source_tags = ["agni-leader"]
  target_tags = ["agni-member"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.member_service_port)]
  }
}

resource "google_secret_manager_secret_iam_member" "security_cell" {
  for_each = var.service_account_email != "" ? var.security_cell_secret_ids : toset([])

  project   = var.project
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

resource "google_artifact_registry_repository_iam_member" "security_cell" {
  count = (
    var.service_account_email != "" &&
    var.security_cell_artifact_repository_location != "" &&
    var.security_cell_artifact_repository_name != ""
  ) ? 1 : 0

  project    = var.project
  location   = var.security_cell_artifact_repository_location
  repository = var.security_cell_artifact_repository_name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.service_account_email}"
}
