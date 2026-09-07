variable "project" {
  type = string
}

variable "zone" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "coreos"
}

variable "source_instance_template" {
  description = "GCE source instance template name or self link."
  type        = string
}

variable "subnetwork" {
  description = "Subnetwork id or self link."
  type        = string
}

variable "ipv4_by_slot" {
  description = "Stable slot-to-private-IPv4 mapping supplied by the regional network."
  type        = map(string)
}

variable "enable_ipv6" {
  type    = bool
  default = true
}

variable "common_metadata" {
  type    = map(string)
  default = {}
}

variable "common_tags" {
  type    = list(string)
  default = []
}

variable "nodes" {
  description = "CoreOS node definitions keyed by regional slot 0..11. Workload/domain meaning belongs to the caller."
  type = map(object({
    metadata              = optional(map(string), {})
    tags                  = optional(list(string), [])
    service_account_email = optional(string, "")
    user_data             = optional(string, "")
  }))

  validation {
    condition = alltrue([
      for slot in keys(var.nodes) :
      can(tonumber(slot)) && tonumber(slot) >= 0 && tonumber(slot) <= 11 && floor(tonumber(slot)) == tonumber(slot)
    ])
    error_message = "nodes keys must be integer regional slots 0 through 11."
  }
}
