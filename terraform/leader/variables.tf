variable "project" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "network" { type = string }
variable "subnetwork_name" { type = string }
variable "template_name" { type = string }
variable "cloudflare_zone_id" { type = string }
variable "cloudflare_hostname" { type = string }

variable "name_prefix" {
  type    = string
  default = "agni-leader"
}

variable "subnetwork_ipv4_cidr" {
  type = string
  validation {
    condition     = can(cidrhost(var.subnetwork_ipv4_cidr, 0)) && tonumber(split("/", var.subnetwork_ipv4_cidr)[1]) == 28
    error_message = "subnetwork_ipv4_cidr must be an IPv4 /28."
  }
}

variable "member_source_ranges" {
  description = "Private CIDRs whose members may use leader Squid"
  type        = list(string)
}

variable "member_upstream_ips" {
  description = "Private member IPs Nginx may reverse-proxy to across any Agni blocks"
  type        = list(string)
  default     = []
}

variable "member_upstream_port" {
  type    = number
  default = 8080
}

variable "member_upstream_scheme" {
  description = "Protocol used by the Agni leader when reverse-proxying to members."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https"], var.member_upstream_scheme)
    error_message = "member_upstream_scheme must be http or https."
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

variable "service_account_email" {
  type    = string
  default = "dev-builder@dashxd.iam.gserviceaccount.com"
}

variable "ssh_public_key_file" {
  type    = string
  default = "../coreos-jumphost.pub"
}

variable "ignition_file" {
  type    = string
  default = "../config.ign"
}

variable "network_tags" {
  type    = list(string)
  default = []
}
