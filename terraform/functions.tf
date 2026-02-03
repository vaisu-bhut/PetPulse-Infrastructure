# Build zip from PetPulse-Serverless directory
# Note: You need to manually create email-sender.zip before terraform apply:
# cd ../../PetPulse-Serverless && zip -r ../PetPulse-Infrastructure/terraform/email-sender.zip index.js package.json
resource "google_storage_bucket_object" "function_zip" {
  name   = "source-${filemd5("email-sender.zip")}.zip"
  bucket = google_storage_bucket.videos.name
  source = "email-sender.zip"
}

# The Cloud Function
resource "google_cloudfunctions2_function" "email_sender" {
  name        = "email-sender-${var.environment}"
  description = "Sends email alerts via SendGrid triggered by Pub/Sub"
  location    = "us-east1" # Gen 2 requires regional location

  build_config {
    runtime     = "nodejs20"
    entry_point = "sendAlertEmail"
    source {
      storage_source {
        bucket = google_storage_bucket.videos.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M" # Minimum for Gen 2
    timeout_seconds    = 60

    environment_variables = {
      SENDGRID_API_KEY = var.sendgrid_api_key
      FRONTEND_DOMAIN  = var.domain_name
    }

    service_account_email = data.google_compute_default_service_account.default.email
  }

  event_trigger {
    trigger_region = "us-east1" # Must match function location
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.alert_email_topic.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}

# Data source for default service account if not already defined
data "google_compute_default_service_account" "default" {
}
