output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_location" {
  value = google_container_cluster.primary.location
}

output "sql_instance_ip" {
  value = google_sql_database_instance.instance.ip_address.0.ip_address
}

output "db_user" {
  value = google_sql_user.users.name
}

output "db_password" {
  value     = google_sql_user.users.password
  sensitive = true
}

output "gemini_api_key" {
  value     = var.gemini_api_key
  sensitive = true
}

output "static_ip_name" {
  value = google_compute_global_address.static_ip.name
}

output "managed_cert_name" {
  value = google_compute_managed_ssl_certificate.default.name
}

output "domain_name" {
  value = var.domain_name
}

output "gcs_bucket_name" {
  value = google_storage_bucket.videos.name
}
