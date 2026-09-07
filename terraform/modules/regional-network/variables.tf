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
  description = "Regional IPv4 CIDR. Google Cloud reserves the first two and last two addresses; /29 is the smallest supported primary subnet."
  type        = string

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

  validation {
    condition     = contains(["EXTERNAL", "INTERNAL"], var.ipv6_access_type)
    error_message = "ipv6_access_type must be EXTERNAL or INTERNAL."
  }
}

variable "private_ip_google_access" {
  description = "Allow internal-IP-only VMs in the subnet to reach supported Google APIs and serverless endpoints without public IPv4."
  type        = bool
  default     = true
}
