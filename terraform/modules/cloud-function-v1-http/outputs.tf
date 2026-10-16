output "name" {
  value = google_cloudfunctions_function.this.name
}

output "region" {
  value = google_cloudfunctions_function.this.region
}

output "uri" {
  value = google_cloudfunctions_function.this.https_trigger_url
}
