variable "template_name" {
  description = "Existing Compute Engine instance template name"
  type        = string
  default     = "ec2-micro-coreos-stable-42-20250623-3-1-usw1-02"
}

variable "instance_name_prefix" {
  description = "Prefix for the generated CoreOS instance name"
  type        = string
  default     = "coreos"
}

variable "region" {
  description = "GCP region containing the instance template"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "Zone for the instance"
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
  description = "Name for the /28 CoreOS subnetwork block"
  type        = string
}

variable "subnetwork_ipv4_cidr" {
  description = "IPv4 /28 containing 16 total addresses and 12 GCP-usable VM addresses"
  type        = string

  validation {
    condition     = can(cidrhost(var.subnetwork_ipv4_cidr, 0)) && tonumber(split("/", var.subnetwork_ipv4_cidr)[1]) == 28
    error_message = "subnetwork_ipv4_cidr must be a valid IPv4 /28 CIDR."
  }
}

variable "vm_slot" {
  description = "Stable CoreOS slot 0-11. Slot N maps to Redis DB N and IPv4 host N+2 in the /28."
  type        = number
  default     = 0

  validation {
    condition     = var.vm_slot >= 0 && var.vm_slot <= 11 && floor(var.vm_slot) == var.vm_slot
    error_message = "vm_slot must be an integer from 0 through 11."
  }
}

variable "enable_ipv6" {
  description = "Create the subnet as dual-stack and attach IPv6 to the VM"
  type        = bool
  default     = true
}

variable "ipv6_access_type" {
  description = "IPv6 access type for the dual-stack subnet"
  type        = string
  default     = "EXTERNAL"

  validation {
    condition     = contains(["EXTERNAL", "INTERNAL"], var.ipv6_access_type)
    error_message = "ipv6_access_type must be EXTERNAL or INTERNAL."
  }
}

variable "service_account_email" {
  description = "Optional service account email to attach to the instance"
  type        = string
  default     = "dev-builder@dashxd.iam.gserviceaccount.com"
}

variable "ssh_public_key_file" {
  description = "Path to the SSH public key used for the core user"
  type        = string
  default     = "coreos-jumphost.pub"
}

variable "network_tags" {
  description = "Additional network tags. squid-client is always applied."
  type        = list(string)
  default     = []
}
