variable "project" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "network" { type = string }
variable "subnetwork_name" { type = string }

variable "ipv4_cidr" {
  type = string
  validation {
    condition     = can(cidrhost(var.ipv4_cidr, 0)) && tonumber(split("/", var.ipv4_cidr)[1]) == 29
    error_message = "Astrochicken ipv4_cidr must be a valid IPv4 /29 CIDR."
  }
}

variable "source_instance_template" { type = string }

variable "service_account_email" {
  type    = string
  default = ""
}

variable "function_invoker_members" {
  type    = list(string)
  default = []
}

variable "gen1_functions" {
  type = map(object({
    runtime               = string
    entry_point           = string
    source_archive_bucket = string
    source_archive_object = string
    service_account_email = optional(string, "")
    available_memory_mb   = optional(number, 256)
    timeout_seconds       = optional(number, 60)
    environment_variables = optional(map(string), {})
    labels                = optional(map(string), {})
  }))
  default = {}
}

variable "gen2_functions" {
  type = map(object({
    runtime               = string
    entry_point           = string
    source_archive_bucket = string
    source_archive_object = string
    service_account_email = optional(string, "")
    available_memory      = optional(string, "256M")
    timeout_seconds       = optional(number, 60)
    min_instance_count    = optional(number, 0)
    max_instance_count    = optional(number, 1)
    environment_variables = optional(map(string), {})
  }))
  default = {}
}
