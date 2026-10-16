terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "google_cloudfunctions2_function" "this" {
  project  = var.project
  location = var.region
  name     = var.name

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = var.source_archive_bucket
        object = var.source_archive_object
      }
    }
  }

  service_config {
    ingress_settings        = var.ingress_settings
    available_memory        = var.available_memory
    timeout_seconds         = var.timeout_seconds
    min_instance_count      = var.min_instance_count
    max_instance_count      = var.max_instance_count
    service_account_email   = var.service_account_email == "" ? null : var.service_account_email
    environment_variables   = var.environment_variables
  }
}

resource "google_cloud_run_service_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project  = google_cloudfunctions2_function.this.project
  location = google_cloudfunctions2_function.this.location
  service  = google_cloudfunctions2_function.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
