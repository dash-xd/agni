output "image_id" {
  value = google_compute_image.agni_coreos.id
}

output "image_self_link" {
  value = google_compute_image.agni_coreos.self_link
}

output "image_name" {
  value = google_compute_image.agni_coreos.name
}

output "image_family" {
  value = google_compute_image.agni_coreos.family
}

output "staging_bucket" {
  value = local.staging_bucket
}
