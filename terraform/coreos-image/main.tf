terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 8.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
}

locals {
  staging_bucket = var.create_staging_bucket ? google_storage_bucket.image_staging[0].name : var.staging_bucket_name
}

resource "google_storage_bucket" "image_staging" {
  count = var.create_staging_bucket ? 1 : 0

  name                        = var.staging_bucket_name
  project                     = var.project_id
  location                    = var.staging_bucket_location
  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_image" "agni_coreos" {
  project     = var.project_id
  name        = var.image_name
  family      = var.image_family
  description = var.image_description

  raw_disk {
    source = "https://storage.googleapis.com/${local.staging_bucket}/${var.image_object}"
  }

  labels = merge({
    os      = "agni-coreos"
    purpose = "podman-production"
  }, var.labels)

  lifecycle {
    create_before_destroy = true
  }
}
