output "addresses" {
  value = {
    for key, address in google_compute_address.this : key => {
      name      = address.name
      address   = address.address
      id        = address.id
      self_link = address.self_link
    }
  }
}
