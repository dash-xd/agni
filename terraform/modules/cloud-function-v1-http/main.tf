terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "google_cloudfunctions_function" "this" {
  project = var.project
  region  = var.region
  name    = var.name

  runtime     = var.runtime
  entry_point = var.entry_point

  source_archive_bucket = var.source_archive_bucket
  source_archive_object = var.source_archive_object

  trigger_http                 = true
  ingress_settings             = var.ingress_settings
  https_trigger_security_level = "SECURE_ALWAYS"
  available_memory_mb          = var.available_memory_mb
  timeout                      = var.timeout_seconds
  service_account_email        = var.service_account_email == "" ? null : var.service_account_email
  environment_variables        = var.environment_variables
  labels                       = var.labels
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project        = google_cloudfunctions_function.this.project
  region         = google_cloudfunctions_function.this.region
  cloud_function = google_cloudfunctions_function.this.name
  role           = "roles/cloudfunctions.invoker"
  member         = each.value
}
