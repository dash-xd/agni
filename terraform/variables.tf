variable "template_name" {
  description = "Existing Compute Engine instance template name"
  type        = string
  default     = "ec2-micro-coreos-stable-42-20250623-3-1-usw1-02"
}

variable "instance_name_prefix" {
  description = "Prefix for generated CoreOS instance names"
  type        = string
  default     = "coreos"
}

variable "region" {
  description = "GCP region containing the instance template"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "Zone for the instances"
  type        = string
  default     = "us-west1-b"
}

variable "project" {
  description = "GCP project ID"
  type        = string
  default     = "dashxd"
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
  description = "CoreOS slots to deploy. Slots 0-11 map 1:1 to Redis DBs 0-11 and IPv4 hosts 2-13. Redis DBs 12-15 remain uncoupled."
  type        = set(number)
  default     = [0]

  validation {
    condition = alltrue([
      for slot in var.vm_slots : slot >= 0 && slot <= 11 && floor(slot) == slot
    ])
    error_message = "Every vm_slots entry must be an integer from 0 through 11."
  }
}

variable "leader_slot" {
  description = "VM slot that acts as the block leader, Squid egress proxy, and Nginx entry reverse proxy"
  type        = number
  default     = 0

  validation {
    condition     = var.leader_slot >= 0 && var.leader_slot <= 11 && floor(var.leader_slot) == var.leader_slot
    error_message = "leader_slot must be an integer from 0 through 11."
  }
}

variable "allocate_leader_public_ipv4" {
  description = "Reserve and attach a regional external IPv4 address to the leader"
  type        = bool
  default     = true
}

variable "leader_public_ports" {
  description = "Fallback TCP ports exposed publicly when Cloudflare HTTPS is disabled"
  type        = list(string)
  default     = ["80"]
}

variable "nginx_upstream_port" {
  description = "Port on member CoreOS instances to which the leader Nginx proxy forwards requests"
  type        = number
  default     = 8080

  validation {
    condition     = var.nginx_upstream_port >= 1 && var.nginx_upstream_port <= 65535
    error_message = "nginx_upstream_port must be between 1 and 65535."
  }
}

variable "enable_cloudflare_https" {
  description = "Create a proxied Cloudflare DNS record and 7-day Origin CA certificate for the leader"
  type        = bool
  default     = false
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID containing cloudflare_hostname"
  type        = string
  default     = ""
}

variable "cloudflare_hostname" {
  description = "Fully qualified hostname proxied through Cloudflare to the leader public IPv4"
  type        = string
  default     = ""
}

variable "enable_ipv6" {
  description = "Create the subnet as dual-stack and attach IPv6 to each VM"
  type        = bool
  default     = true
}

variable "ipv6_access_type" {
  description = "IPv6 access type for the dual-stack subnet"
  type        = string
  default     = "INTERNAL"

  validation {
    condition     = contains(["EXTERNAL", "INTERNAL"], var.ipv6_access_type)
    error_message = "ipv6_access_type must be EXTERNAL or INTERNAL."
  }
}

variable "service_account_email" {
  description = "Optional service account email to attach to each instance"
  type        = string
  default     = "dev-builder@dashxd.iam.gserviceaccount.com"
}

variable "ssh_public_key_file" {
  description = "Path to the SSH public key used for the core user"
  type        = string
  default     = "coreos-jumphost.pub"
}

variable "network_tags" {
  description = "Additional network tags"
  type        = list(string)
  default     = []
}
