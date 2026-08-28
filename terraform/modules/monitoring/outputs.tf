output "log_bucket_name" {
  description = "Short name (bucket_id) of the Cloud Logging bucket for application logs"
  value       = google_logging_project_bucket_config.app.bucket_id
}

output "log_bucket_id" {
  description = "Fully qualified ID of the Cloud Logging bucket"
  value       = google_logging_project_bucket_config.app.id
}

output "log_sink_writer_identity" {
  description = "Service identity the log sink writes with"
  value       = google_logging_project_sink.app.writer_identity
}

output "alert_policy_ids" {
  description = "Map of alert policy short names to their resource IDs"
  value = {
    cpu_high           = google_monitoring_alert_policy.cpu_high.id
    memory_high        = google_monitoring_alert_policy.memory_high.id
    instance_count_low = google_monitoring_alert_policy.instance_count_low.id
  }
}

output "trace_enabled" {
  description = "Whether Cloud Trace configuration is enabled for this environment"
  value       = var.enable_trace
}

output "trace_sampling_rate" {
  description = "Trace sampling rate configured for this environment (0.0–1.0)"
  value       = var.trace_sampling_rate
}

output "trace_env_vars" {
  description = "Environment variables the cloudrun module injects into the container to configure client-side trace sampling (empty map when tracing is disabled)"
  value       = local.trace_env_vars
}
