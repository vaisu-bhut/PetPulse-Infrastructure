output "gemini_api_key" {
  value     = var.gemini_api_key
  sensitive = true
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "gke_location" {
  value = google_container_cluster.primary.location
}

output "sql_instance_connection_name" {
  value = google_sql_database_instance.instance.connection_name
}

output "sql_instance_ip" {
  value = google_sql_database_instance.instance.private_ip_address
}

output "db_user" {
  value = google_sql_user.users.name
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
