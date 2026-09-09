variable "project_id" {
  type = string
}

variable "staging_bucket_name" {
  description = "GCS bucket containing the COSA GCP image archive"
  type        = string
}

variable "staging_bucket_location" {
  type    = string
  default = "US"
}

variable "create_staging_bucket" {
  description = "Create the staging bucket. Set false when the deployment repository owns it separately."
  type        = bool
  default     = false
}

variable "image_object" {
  description = "Object path, relative to the staging bucket, of the COSA *-gcp.*.tar.gz artifact"
  type        = string
}

variable "image_name" {
  description = "Immutable Compute Engine image name; normally contains the Agni source commit"
  type        = string
}

variable "image_family" {
  type    = string
  default = "agni-coreos"
}

variable "image_description" {
  type    = string
  default = "Agni production Fedora CoreOS image for Podman workloads"
}

variable "labels" {
  type    = map(string)
  default = {}
}
