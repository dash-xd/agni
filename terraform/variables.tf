variable "template_name" {
  type    = string
  default = "ec2-micro-coreos-stable-42-20250623-3-1-usw1-02"
}

variable "instance_name_prefix" {
  type    = string
  default = "coreos"
}

variable "region" {
  type    = string
  default = "us-west1"
}

variable "zone" {
  type    = string
  default = "us-west1-b"
}

variable "project" {
  type    = string
  default = "dashxd"
}

variable "network" {
  description = "Custom-mode VPC network name or self link"
  type        = string
}

variable "subnetwork_name" {
  description = "Name for this 16-address CoreOS block"
  type        = string
}

variable "subnetwork_ipv4_cidr" {
  description = "IPv4 /28: 16 total addresses, 12 GCP-usable VM addresses"
  type        = string

  validation {
    condition     = can(cidrhost(var.subnetwork_ipv4_cidr, 0)) && tonumber(split("/", var.subnetwork_ipv4_cidr)[1]) == 28
    error_message = "subnetwork_ipv4_cidr must be a valid IPv4 /28 CIDR."
  }
}

variable "vm_slots" {
  description = "CoreOS slots 0-11; each maps to the same-numbered Redis DB. Redis DBs 12-15 remain uncoupled."
  type        = set(number)
  default     = [0]

  validation {
    condition     = alltrue([for slot in var.vm_slots : slot >= 0 && slot <= 11 && floor(slot) == slot])
    error_message = "Every vm_slots entry must be an integer from 0 through 11."
  }
}

variable "egress_proxy_ip" {
  description = "Internal IPv4 of the single Agni leader/Squid proxy"
  type        = string
}

variable "member_service_port" {
  description = "Application port exposed by members to the global leader Nginx"
  type        = number
  default     = 8080

  validation {
    condition     = var.member_service_port >= 1 && var.member_service_port <= 65535
    error_message = "member_service_port must be between 1 and 65535."
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

variable "service_account_email" {
  type    = string
  default = "dev-builder@dashxd.iam.gserviceaccount.com"
}

variable "ssh_public_key_file" {
  type    = string
  default = "coreos-jumphost.pub"
}

variable "network_tags" {
  type    = list(string)
  default = []
}
