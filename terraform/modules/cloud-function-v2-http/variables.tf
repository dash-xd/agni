variable "project" { type = string }
variable "region" { type = string }
variable "name" { type = string }
variable "runtime" { type = string }
variable "entry_point" { type = string }
variable "source_archive_bucket" { type = string }
variable "source_archive_object" { type = string }

variable "ingress_settings" {
  description = "Cloud Run functions ingress policy selected by the caller."
  type        = string

  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "ingress_settings must be ALLOW_ALL, ALLOW_INTERNAL_ONLY, or ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "invoker_members" {
  description = "IAM principals granted roles/run.invoker on the underlying Cloud Run service."
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  type    = string
  default = ""
}

variable "available_memory" {
  type    = string
  default = "256M"
}

variable "timeout_seconds" {
  type    = number
  default = 60
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "max_instance_count" {
  type    = number
  default = 1
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}
