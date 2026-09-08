variable "zone_id" {
  description = "Cloudflare zone ID that owns the TXT records."
  type        = string
}

variable "records" {
  description = "Provider-neutral TXT records projected by cfxd/xdroute into Terraform."
  type = map(object({
    name    = string
    content = string
    ttl     = optional(number, 1)
    comment = optional(string)
    tags    = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for record in values(var.records) : trimspace(record.name) != "" && trimspace(record.content) != ""])
    error_message = "Every cfxd TXT record must have a non-empty name and content."
  }
}
