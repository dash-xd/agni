variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "network" {
  description = "VPC network name or self link."
  type        = string
}

variable "name" {
  description = "Regional subnetwork name."
  type        = string
}

variable "ipv4_cidr" {
  description = "Regional IPv4 /28. GCE reserves four addresses, leaving twelve VM-usable addresses."
  type        = string

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

  validation {
    condition     = contains(["EXTERNAL", "INTERNAL"], var.ipv6_access_type)
    error_message = "ipv6_access_type must be EXTERNAL or INTERNAL."
  }
}

variable "private_ip_google_access" {
  type    = bool
  default = true
}
