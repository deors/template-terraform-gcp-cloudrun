output "app_url" {
  description = "Primary application URL: https://<app_fqdn> with a custom domain, otherwise the run.app URL"
  value       = module.cloudrun.app_url
}

output "app_fqdn" {
  description = "Custom-domain FQDN (empty without main_domain)"
  value       = module.cloudrun.app_fqdn
}

output "service_url" {
  description = "Default run.app URL of the Cloud Run service"
  value       = module.cloudrun.service_url
}

output "service_name" {
  description = "Cloud Run service name"
  value       = module.cloudrun.service_name
}

output "lb_ip_address" {
  description = "External IP address of the load balancer (null without main_domain)"
  value       = module.cloudrun.lb_ip_address
}

output "image_repository" {
  description = "Artifact Registry path that proxies the container registry; deployed images are <image_repository>/<container_image>"
  value       = module.cloudrun.image_repository
}

output "traffic_split_enabled" {
  description = "Whether deployments shift traffic gradually (false: all traffic to the latest revision)"
  value       = module.cloudrun.traffic_split_enabled
}

output "service_account_email" {
  description = "Runtime service account of the Cloud Run service"
  value       = module.cloudrun.service_account_email
}

output "log_bucket_name" {
  description = "Cloud Logging bucket holding the application logs"
  value       = module.monitoring.log_bucket_name
}

output "auth_mode" {
  description = "How requests are authenticated before reaching the container"
  value       = module.cloudrun.auth_mode
}

output "auth_test_identity_email" {
  description = "Service account used by end-to-end tests and verification"
  value       = module.cloudrun.auth_test_identity_email
}

output "auth_token_audience" {
  description = "Audience of the test identity's signed JWT (<app_url>/*)"
  value       = module.cloudrun.auth_token_audience
}

output "auth_token_command" {
  description = "Shell command that prints a 10-minute JWT signed by the test identity for app_url"
  value       = module.cloudrun.auth_token_command
}
