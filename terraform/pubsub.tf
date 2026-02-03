resource "google_pubsub_topic" "alert_email_topic" {
  name = "alert-email-topic-${var.environment}"
}
