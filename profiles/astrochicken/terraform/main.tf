terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

locals {
  execution_service_ip = cidrhost(var.ipv4_cidr, 4)
  egress_service_ip    = cidrhost(var.ipv4_cidr, 5)
  function_invoker_members = distinct(concat(
    var.function_invoker_members,
    var.service_account_email == "" ? [] : ["serviceAccount:${var.service_account_email}"]
  ))
}

module "region" {
  source = "./modules/regional-cell"

  project                  = var.project
  region                   = var.region
  zone                     = var.zone
  network                  = var.network
  subnetwork_name          = var.subnetwork_name
  ipv4_cidr                = var.ipv4_cidr
  source_instance_template = var.source_instance_template
  enable_ipv6              = true
  private_ip_google_access = true

  internal_addresses = {
    execution = {
      name        = "${var.subnetwork_name}-execution"
      address     = local.execution_service_ip
      description = "Astrochicken Nginx execution service address"
    }
    egress = {
      name        = "${var.subnetwork_name}-egress"
      address     = local.egress_service_ip
      description = "Astrochicken Squid egress service address"
    }
  }

  nodes = {
    "0" = {
      metadata = {
        "smoke-role"                 = "gateway"
        "smoke-execution-service-ip" = local.execution_service_ip
        "smoke-egress-service-ip"    = local.egress_service_ip
      }
      alias_ip_ranges = [
        { ip_cidr_range = "${local.execution_service_ip}/32" },
        { ip_cidr_range = "${local.egress_service_ip}/32" },
      ]
      service_account_email = var.service_account_email
    }
    "1" = {
      metadata = { "smoke-role" = "world" }
      service_account_email = var.service_account_email
    }
  }
}

module "gen1_functions" {
  for_each = var.gen1_functions
  source   = "./modules/cloud-function-v1-http"

  project               = var.project
  region                = var.region
  name                  = each.key
  runtime               = each.value.runtime
  entry_point           = each.value.entry_point
  source_archive_bucket = each.value.source_archive_bucket
  source_archive_object = each.value.source_archive_object
  ingress_settings      = "ALLOW_INTERNAL_ONLY"
  invoker_members       = local.function_invoker_members
  service_account_email = each.value.service_account_email
  available_memory_mb   = each.value.available_memory_mb
  timeout_seconds       = each.value.timeout_seconds
  environment_variables = each.value.environment_variables
  labels                = merge({ "smoke-role" = "shadow" }, each.value.labels)
}

module "gen2_functions" {
  for_each = var.gen2_functions
  source   = "./modules/cloud-function-v2-http"

  project               = var.project
  region                = var.region
  name                  = each.key
  runtime               = each.value.runtime
  entry_point           = each.value.entry_point
  source_archive_bucket = each.value.source_archive_bucket
  source_archive_object = each.value.source_archive_object
  ingress_settings      = "ALLOW_INTERNAL_ONLY"
  invoker_members       = local.function_invoker_members
  service_account_email = each.value.service_account_email
  available_memory      = each.value.available_memory
  timeout_seconds       = each.value.timeout_seconds
  min_instance_count    = each.value.min_instance_count
  max_instance_count    = each.value.max_instance_count
  environment_variables = each.value.environment_variables
}
