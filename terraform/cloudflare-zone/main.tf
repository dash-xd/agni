terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.23"
    }
  }

  required_version = ">= 1.3.0"

  backend "gcs" {}
}

provider "cloudflare" {}

variable "zone_id" {
  description = "Cloudflare zone ID managed by this state"
  type        = string
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}

output "ssl_mode" {
  value = cloudflare_zone_setting.ssl.value
}
