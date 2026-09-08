output "records" {
  description = "Cloudflare TXT records managed by this module."
  value = {
    for key, record in cloudflare_dns_record.txt : key => {
      id      = record.id
      name    = record.name
      content = record.content
    }
  }
}
