output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "sql_instance_connection_name" {
  value = google_sql_database_instance.instance.connection_name
}

output "sql_instance_ip" {
  value = google_sql_database_instance.instance.private_ip_address
}
