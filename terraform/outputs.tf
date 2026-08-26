output "instance_name" {
  value = google_compute_instance_from_template.vm.name
}

output "instance_id" {
  value = google_compute_instance_from_template.vm.instance_id
}

output "zone" {
  value = google_compute_instance_from_template.vm.zone
}

output "internal_ip" {
  value = google_compute_instance_from_template.vm.network_interface[0].network_ip
}
