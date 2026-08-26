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
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Optional subnetwork name or self link"
  type        = string
  default     = ""
}

variable "internal_ip" {
  description = "Optional static internal IP. Leave empty to let GCE allocate one from the subnet."
  type        = string
  default     = ""
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
