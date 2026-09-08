terraform {
  required_version = ">= 1.3.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.23"
    }
  }
}

resource "cloudflare_dns_record" "txt" {
  for_each = var.records

  zone_id = var.zone_id
  type    = "TXT"
  name    = each.value.name
  content = each.value.content
  ttl     = each.value.ttl
  comment = each.value.comment
  tags    = each.value.tags
}
