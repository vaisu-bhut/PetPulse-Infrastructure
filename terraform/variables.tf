variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud Region"
  type        = string
}

variable "zone" {
  description = "The Google Cloud Zone"
  type        = string
}

variable "environment" {
  description = "The environment environment (preview or production)"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "subnet_cidr" {
  description = "The CIDR block for the primary subnet"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The CIDR block for the GKE master"
  type        = string
}

variable "gke_num_nodes" {
  description = "Number of nodes in the GKE cluster"
  type        = number
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
}

variable "db_tier" {
  description = "Machine type for Cloud SQL instance"
  type        = string
}

variable "gemini_api_key" {
  description = "API Key for Gemini Service"
  type        = string
  sensitive   = true
}
