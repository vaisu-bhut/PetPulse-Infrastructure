# Enable APIs
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dns" {
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.1.0.0/16" # Example secondary range, consider making variable if needed strictly no defaults
  }

  secondary_ip_range {
    range_name    = "service-ranges"
    ip_cidr_range = "10.2.0.0/20" # Example secondary range
  }
}

# Private Service Access for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.environment}-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  depends_on              = [google_project_service.servicenetworking]
}

# Cloud SQL
resource "google_sql_database_instance" "instance" {
  name             = "${var.environment}-db-instance"
  region           = var.region
  database_version = "POSTGRES_15"

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.sqladmin
  ]

  settings {
    tier = var.db_tier
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }
  deletion_protection = false # For easier cleanup in this demo context
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "users" {
  name     = "petpulse-user"
  instance = google_sql_database_instance.instance.name
  password = random_password.db_password.result
}

resource "google_sql_database" "database" {
  name     = "petpulse"
  instance = google_sql_database_instance.instance.name
  depends_on = [google_sql_user.users]
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name                = "${var.environment}-gke-cluster"
  location            = var.zone
  deletion_protection = false

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_size_gb = var.gke_disk_size
  }

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-ranges"
    services_secondary_range_name = "service-ranges"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Ensure we have clean dependency on networking
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.container
  ]
}

# Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.environment}-node-pool"
  cluster    = google_container_cluster.primary.id
  location   = var.zone
  node_count = var.gke_num_nodes

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_disk_size

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 3 # Simple autoscaling config
  }
}

# Secrets Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.environment}-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# --- New Resources for SSL & Domains ---

# DNS Managed Zone (Data Source)
data "google_dns_managed_zone" "zone" {
  name       = var.dns_zone_name
  depends_on = [google_project_service.dns]
}

# Global Static IP
resource "google_compute_global_address" "static_ip" {
  name = "petpulse-${var.environment}-ip"
}

# DNS Record Set (A Record)
resource "google_dns_record_set" "a_record" {
  name         = var.domain_name
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.zone.name
  rrdatas      = [google_compute_global_address.static_ip.address]
}

# Managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "default" {
  name = "petpulse-${var.environment}-cert"

  managed {
    domains = [var.domain_name]
  }
}

# GCS Bucket for Videos
resource "google_storage_bucket" "videos" {
  name          = "petpulse-videos-${var.environment}"
  location      = "US" # Multi-region
  force_destroy = true

  uniform_bucket_level_access = true
  
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
}
