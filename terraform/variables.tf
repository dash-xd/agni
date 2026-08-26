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

variable "leader_state_bucket" {
  description = "GCS bucket containing the single Agni leader Terraform state"
  type        = string
}

variable "leader_state_prefix" {
  description = "GCS Terraform backend prefix for the single Agni leader state"
  type        = string
  default     = "terraform/agni-leader"
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

variable "member_metadata" {
  description = "Additional deployment-controlled metadata merged into every member. Reserved agni-* keys cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.member_metadata) : !startswith(key, "agni-")])
    error_message = "member_metadata may not override reserved agni-* metadata keys."
  }
}

variable "member_metadata_by_slot" {
  description = "Additional deployment-controlled metadata for individual member slots. Keys are slot numbers encoded as strings."
  type        = map(map(string))
  default     = {}

  validation {
    condition = alltrue([
      for slot, metadata in var.member_metadata_by_slot :
      can(tonumber(slot)) && tonumber(slot) >= 0 && tonumber(slot) <= 11 && floor(tonumber(slot)) == tonumber(slot) &&
      alltrue([for key in keys(metadata) : !startswith(key, "agni-")])
    ])
    error_message = "member_metadata_by_slot keys must be integer slots 0..11 and may not override reserved agni-* metadata keys."
  }
}

variable "security_cell_secret_ids" {
  description = "Secret Manager secret IDs readable by the Agni runtime service account for a hosted security cell."
  type        = set(string)
  default     = []
}

variable "security_cell_artifact_repository_location" {
  type    = string
  default = ""
}

variable "security_cell_artifact_repository_name" {
  type    = string
  default = ""
}
