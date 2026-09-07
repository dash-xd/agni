variable "project" { type = string }
variable "region" { type = string }
variable "name" { type = string }
variable "runtime" { type = string }
variable "entry_point" { type = string }
variable "source_archive_bucket" { type = string }
variable "source_archive_object" { type = string }

variable "ingress_settings" {
  description = "Cloud Functions ingress policy selected by the caller."
  type        = string

  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "ingress_settings must be ALLOW_ALL, ALLOW_INTERNAL_ONLY, or ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "invoker_members" {
  description = "IAM principals allowed to invoke this 1st gen HTTP function."
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  type    = string
  default = ""
}

variable "available_memory_mb" {
  type    = number
  default = 256
}

variable "timeout_seconds" {
  type    = number
  default = 60
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}
