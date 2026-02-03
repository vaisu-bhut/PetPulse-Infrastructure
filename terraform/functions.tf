# Upload the zip to the bucket
resource "google_storage_bucket_object" "function_zip" {
  name   = "source-${filemd5("email-sender.zip")}.zip"
  bucket = google_storage_bucket.videos.name
  source = "email-sender.zip"
}

# The Cloud Function
resource "google_cloudfunctions_function" "email_sender" {
  name        = "email-sender-${var.environment}"
  description = "Sends email alerts via SendGrid triggered by Pub/Sub"
  runtime     = "nodejs20"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.videos.name
  source_archive_object = google_storage_bucket_object.function_zip.name


  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.alert_email_topic.name
  }

  entry_point = "sendAlertEmail"

  environment_variables = {
    SENDGRID_API_KEY = var.sendgrid_api_key
    FRONTEND_DOMAIN  = var.domain_name
  }

  service_account_email = data.google_compute_default_service_account.default.email # Use default or create custom
}

# Data source for default service account if not already defined
data "google_compute_default_service_account" "default" {
}
