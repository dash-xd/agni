output "name" {
  value = google_cloudfunctions2_function.this.name
}

output "region" {
  value = google_cloudfunctions2_function.this.location
}

output "uri" {
  value = google_cloudfunctions2_function.this.service_config[0].uri
}
