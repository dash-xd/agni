terraform {
  required_version = ">= 1.5.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.23"
    }
  }
}

provider "cloudflare" {}

variable "account_id" {
  type = string
}
variable "service" {
  type = string
}
variable "worker_file" {
  type = string
}
variable "sites" {
  type = map(object({
    zone_id   = string
    zone_name = string
  }))
}

resource "cloudflare_workers_script" "placeholder" {
  account_id  = var.account_id
  script_name = var.service
  content     = file(var.worker_file)
  main_module = "worker.mjs"
}

resource "cloudflare_workers_custom_domain" "site" {
  for_each     = var.sites
  account_id   = var.account_id
  hostname     = each.key
  service      = cloudflare_workers_script.placeholder.script_name
  zone_id      = each.value.zone_id
  zone_name    = each.value.zone_name
}

output "managed_hostnames" {
  value = sort(keys(cloudflare_workers_custom_domain.site))
}
