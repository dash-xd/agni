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
    condition     = can(cidrhost(var.ipv4_cidr, 0)) && tonumber(split("/", var.ipv4_cidr)[1]) == 28
    error_message = "ipv4_cidr must be a valid IPv4 /28 CIDR."
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

variable "nodes" {
  description = "Node definitions keyed by regional slot. The caller assigns topology/workload semantics."
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
