output "service_id" {
  description = "ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.this.id
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.this.name
}

output "service_url" {
  description = "Default run.app URL of the service (reachable only from inside the VPC when internal is true)"
  value       = google_cloud_run_v2_service.this.uri
}

output "service_account_email" {
  description = "Email of the runtime service account"
  value       = google_service_account.runtime.email
}

output "artifact_pull_sa_email" {
  description = "Email of the Cloud Run service agent that pulls images from the remote repository"
  value       = local.serverless_agent
}

output "image_repository" {
  description = "Artifact Registry path that proxies container_registry_url; deployed images are <image_repository>/<container_image>"
  value       = local.image_repository
}

output "traffic_split_enabled" {
  description = "Whether the deployment workflow deploys revisions without traffic and shifts it gradually"
  value       = var.enable_traffic_split
}

output "app_url" {
  description = "Primary application URL: https://<app_fqdn> when a custom domain is configured, otherwise the run.app URL"
  value       = local.app_url
}

output "app_fqdn" {
  description = "Custom-domain FQDN served by the load balancer (empty without a custom domain)"
  value       = var.app_fqdn
}

output "lb_ip_address" {
  description = "IP address of the load balancer (null without a custom domain)"
  value       = one(google_compute_address.lb[*].address)
}

# ──────────────────────────────────────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────────────────────────────────────

output "auth_mode" {
  description = "How requests are authenticated before reaching the container"
  value       = "iap"
}

output "auth_test_identity_email" {
  description = "Service account used by end-to-end tests and verification through impersonation"
  value       = google_service_account.test_identity.email
}

output "auth_token_audience" {
  description = "Audience of the test identity's signed JWT: <app_url>/*. A token is valid only for the URL it names."
  value       = local.token_audience
}

output "auth_token_command" {
  description = "Shell command that prints a 10-minute JWT signed by the test identity for app_url; send it as 'Authorization: Bearer <token>'"
  value       = "printf '{\"iss\":\"${google_service_account.test_identity.email}\",\"sub\":\"${google_service_account.test_identity.email}\",\"aud\":\"${local.token_audience}\",\"iat\":%s,\"exp\":%s}' \"$(date +%s)\" \"$(($(date +%s)+600))\" | gcloud iam service-accounts sign-jwt --iam-account=${google_service_account.test_identity.email} --quiet /dev/stdin /dev/stdout 2>/dev/null"
}
