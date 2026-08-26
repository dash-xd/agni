terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.23"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.3.0"

  backend "gcs" {}
}

provider "cloudflare" {}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

locals {
  slots = {
    for slot in var.vm_slots : tostring(slot) => slot
  }

  leader_ip = cidrhost(var.subnetwork_ipv4_cidr, var.leader_slot + 2)
  member_ips = [
    for slot in sort(tolist(var.vm_slots)) : cidrhost(var.subnetwork_ipv4_cidr, slot + 2)
    if slot != var.leader_slot
  ]

  cloudflare_ipv4_cidrs = var.enable_cloudflare_https ? compact(split("\n", trimspace(data.http.cloudflare_ipv4[0].response_body))) : []
}

resource "random_id" "suffix" {
  for_each    = local.slots
  byte_length = 4
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

  lifecycle {
    precondition {
      condition     = contains(var.vm_slots, var.leader_slot)
      error_message = "vm_slots must contain leader_slot."
    }

    precondition {
      condition = !var.enable_cloudflare_https || (
        var.allocate_leader_public_ipv4 &&
        trimspace(var.cloudflare_zone_id) != "" &&
        trimspace(var.cloudflare_hostname) != ""
      )
      error_message = "Cloudflare HTTPS requires allocate_leader_public_ipv4=true plus cloudflare_zone_id and cloudflare_hostname."
    }
  }
}

resource "google_compute_address" "leader" {
  count = var.allocate_leader_public_ipv4 ? 1 : 0

  name         = "${var.subnetwork_name}-leader"
  project      = var.project
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

data "http" "cloudflare_ipv4" {
  count = var.enable_cloudflare_https ? 1 : 0
  url   = "https://www.cloudflare.com/ips-v4"
}

resource "tls_private_key" "leader_origin" {
  count = var.enable_cloudflare_https ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "leader_origin" {
  count = var.enable_cloudflare_https ? 1 : 0

  private_key_pem = tls_private_key.leader_origin[0].private_key_pem
  dns_names       = [var.cloudflare_hostname]

  subject {
    common_name = var.cloudflare_hostname
  }
}

resource "cloudflare_origin_ca_certificate" "leader" {
  count = var.enable_cloudflare_https ? 1 : 0

  csr                = tls_cert_request.leader_origin[0].cert_request_pem
  hostnames          = [var.cloudflare_hostname]
  request_type       = "origin-ecc"
  requested_validity = 7
}

resource "cloudflare_dns_record" "leader" {
  count = var.enable_cloudflare_https ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_hostname
  type    = "A"
  content = google_compute_address.leader[0].address
  ttl     = 1
  proxied = true

  comment = "Agni Terraform-managed CoreOS leader"
}

resource "google_compute_instance_from_template" "vm" {
  for_each = local.slots

  name                     = "${var.instance_name_prefix}-${format("%02d", each.value)}-${random_id.suffix[each.key].hex}"
  zone                     = var.zone
  source_instance_template = "projects/${var.project}/${var.region}/instanceTemplates/${var.template_name}"
  project                  = var.project

  metadata = {
    ssh-keys                        = "core:${file(var.ssh_public_key_file)}"
    user-data                       = file("${path.module}/config.ign")
    agni-role                       = each.value == var.leader_slot ? "leader" : "member"
    agni-leader-ip                  = local.leader_ip
    agni-member-ips                 = join(",", local.member_ips)
    agni-subnet-cidr                = var.subnetwork_ipv4_cidr
    agni-nginx-upstream-port        = tostring(var.nginx_upstream_port)
    agni-redis-db                   = tostring(each.value)
    agni-cloudflare-https           = var.enable_cloudflare_https ? "true" : "false"
    agni-cloudflare-hostname        = var.enable_cloudflare_https ? var.cloudflare_hostname : ""
    agni-origin-certificate-b64     = var.enable_cloudflare_https && each.value == var.leader_slot ? base64encode(cloudflare_origin_ca_certificate.leader[0].certificate) : ""
    agni-origin-private-key-b64     = var.enable_cloudflare_https && each.value == var.leader_slot ? base64encode(tls_private_key.leader_origin[0].private_key_pem) : ""
  }

  tags = distinct(concat(
    ["squid-client", "redis-db-${each.value}"],
    each.value == var.leader_slot ? ["agni-leader"] : ["agni-member"],
    var.network_tags,
  ))

  network_interface {
    subnetwork = google_compute_subnetwork.coreos.id
    network_ip = cidrhost(var.subnetwork_ipv4_cidr, each.value + 2)
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"

    dynamic "access_config" {
      for_each = each.value == var.leader_slot && var.allocate_leader_public_ipv4 ? [1] : []
      content {
        nat_ip       = google_compute_address.leader[0].address
        network_tier = "PREMIUM"
      }
    }

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

resource "google_compute_firewall" "members_to_squid" {
  name    = "${var.subnetwork_name}-members-to-squid"
  project = var.project
  network = var.network

  direction     = "INGRESS"
  source_ranges = [var.subnetwork_ipv4_cidr]
  target_tags   = ["agni-leader"]

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }
}

resource "google_compute_firewall" "leader_to_members" {
  name    = "${var.subnetwork_name}-leader-to-members"
  project = var.project
  network = var.network

  direction   = "INGRESS"
  source_tags = ["agni-leader"]
  target_tags = ["agni-member"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.nginx_upstream_port)]
  }
}

resource "google_compute_firewall" "leader_cloudflare_https" {
  count = var.enable_cloudflare_https ? 1 : 0

  name    = "${var.subnetwork_name}-cloudflare-https"
  project = var.project
  network = var.network

  direction     = "INGRESS"
  source_ranges = local.cloudflare_ipv4_cidrs
  target_tags   = ["agni-leader"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "leader_public_ingress" {
  count = !var.enable_cloudflare_https && var.allocate_leader_public_ipv4 && length(var.leader_public_ports) > 0 ? 1 : 0

  name    = "${var.subnetwork_name}-leader-public"
  project = var.project
  network = var.network

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["agni-leader"]

  allow {
    protocol = "tcp"
    ports    = var.leader_public_ports
  }
}
