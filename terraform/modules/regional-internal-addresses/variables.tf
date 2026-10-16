variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "subnetwork" {
  description = "Subnetwork id or self link containing the internal addresses."
  type        = string
}

variable "addresses" {
  description = "Static regional internal IPv4 reservations keyed by caller-owned semantic name."
  type = map(object({
    name        = string
    address     = string
    description = optional(string, "")
  }))

  default = {}

  validation {
    condition = alltrue([
      for address in values(var.addresses) :
      trimspace(address.name) != "" && trimspace(address.address) != ""
    ])
    error_message = "each internal address reservation requires a non-empty name and address."
  }
}
