variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "network" {
  type = string
}

variable "subnetwork_name" {
  type = string
}

variable "ipv4_cidr" {
  type = string

  validation {
    condition = (
      can(cidrhost(var.ipv4_cidr, 0)) &&
      can(tonumber(split("/", var.ipv4_cidr)[1])) &&
      tonumber(split("/", var.ipv4_cidr)[1]) <= 29
    )
    error_message = "ipv4_cidr must be a valid IPv4 CIDR with prefix length /29 or larger address space."
  }
}

variable "enable_ipv6" {
  type    = bool
  default = true
}

variable "ipv6_access_type" {
  type    = string
  default = "INTERNAL"
}

variable "private_ip_google_access" {
  type    = bool
  default = true
}

variable "node_name_prefix" {
  type    = string
  default = "coreos"
}

variable "source_instance_template" {
  type = string
}

variable "common_metadata" {
  type    = map(string)
  default = {}
}

variable "common_tags" {
  type    = list(string)
  default = []
}

variable "internal_addresses" {
  description = "Static internal address reservations keyed by caller-owned semantic name."
  type = map(object({
    name        = string
    address     = string
    description = optional(string, "")
  }))
  default = {}
}

variable "nodes" {
  description = "Node definitions keyed by address slot. The caller assigns topology/workload semantics."
  type = map(object({
    metadata              = optional(map(string), {})
    tags                  = optional(list(string), [])
    service_account_email = optional(string, "")
    user_data             = optional(string, "")
    alias_ip_ranges = optional(list(object({
      ip_cidr_range         = string
      subnetwork_range_name = optional(string, "")
    })), [])
  }))

  validation {
    condition = alltrue([
      for slot in keys(var.nodes) :
      can(tonumber(slot)) && tonumber(slot) >= 0 && floor(tonumber(slot)) == tonumber(slot)
    ])
    error_message = "nodes keys must be non-negative integer address slots."
  }
}
