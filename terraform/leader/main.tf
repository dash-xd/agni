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

data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"
}

locals {
  leader_ip             = cidrhost(var.subnetwork_ipv4_cidr, 2)
  cloudflare_ipv4_cidrs = compact(split("\n", trimspace(data.http.cloudflare_ipv4.response_body)))
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_compute_subnetwork" "leader" {
  name                     = var.subnetwork_name
  project                  = var.project
  region                   = var.region
  network                  = var.network
  ip_cidr_range            = var.subnetwork_ipv4_cidr
  private_ip_google_access = true
  stack_type               = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"
  ipv6_access_type         = var.enable_ipv6 ? var.ipv6_access_type : null
}

resource "google_compute_address" "leader" {
  name         = "${var.name_prefix}-public"
  project      = var.project
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "tls_private_key" "origin" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem
  dns_names       = [var.cloudflare_hostname]

  subject {
    common_name = var.cloudflare_hostname
  }
}

resource "cloudflare_origin_ca_certificate" "origin" {
  csr                = tls_cert_request.origin.cert_request_pem
  hostnames          = [var.cloudflare_hostname]
  request_type       = "origin-ecc"
  requested_validity = 7
}

resource "cloudflare_dns_record" "leader" {
  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_hostname
  type    = "A"
  content = google_compute_address.leader.address
  proxied = true
  ttl     = 1
  comment = "Agni global ingress leader"
}

resource "google_compute_instance_from_template" "leader" {
  name                     = "${var.name_prefix}-${random_id.suffix.hex}"
  zone                     = var.zone
  source_instance_template = "projects/${var.project}/${var.region}/instanceTemplates/${var.template_name}"
  project                  = var.project

  metadata = {
    ssh-keys                    = "core:${file(var.ssh_public_key_file)}"
    user-data                   = file(var.ignition_file)
    agni-role                   = "leader"
    agni-leader-ip              = local.leader_ip
    agni-member-ips             = join(",", var.member_upstream_ips)
    agni-subnet-cidr            = var.subnetwork_ipv4_cidr
    agni-client-cidrs           = join(",", var.member_source_ranges)
    agni-nginx-upstream-port    = tostring(var.member_upstream_port)
    agni-nginx-upstream-scheme  = var.member_upstream_scheme
    agni-redis-db               = ""
    agni-cloudflare-https       = "true"
    agni-cloudflare-hostname    = var.cloudflare_hostname
    agni-origin-certificate-b64 = base64encode(cloudflare_origin_ca_certificate.origin.certificate)
    agni-origin-private-key-b64 = base64encode(tls_private_key.origin.private_key_pem)
  }

  tags = distinct(concat(["agni-leader", "squid-client"], var.network_tags))

  network_interface {
    subnetwork = google_compute_subnetwork.leader.id
    network_ip = local.leader_ip
    stack_type = var.enable_ipv6 ? "IPV4_IPV6" : "IPV4_ONLY"

    access_config {
      nat_ip       = google_compute_address.leader.address
      network_tier = "PREMIUM"
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

resource "google_compute_firewall" "cloudflare_https" {
  name          = "${var.name_prefix}-cloudflare-https"
  project       = var.project
  network       = var.network
  direction     = "INGRESS"
  source_ranges = local.cloudflare_ipv4_cidrs
  target_tags   = ["agni-leader"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "members_to_squid" {
  name          = "${var.name_prefix}-members-to-squid"
  project       = var.project
  network       = var.network
  direction     = "INGRESS"
  source_ranges = var.member_source_ranges
  target_tags   = ["agni-leader"]

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }
}
