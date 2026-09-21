locals {
  prefix = lower("${var.name}-${var.environment}")

  base_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "terraform"
    platform    = "platform-engineering"
  })

  # Trace sampling is decided client-side; the cloudrun module injects these
  # OpenTelemetry variables into the container.
  trace_env_vars = var.enable_trace ? {
    OTEL_TRACES_SAMPLER     = "parentbased_traceidratio"
    OTEL_TRACES_SAMPLER_ARG = tostring(var.trace_sampling_rate)
  } : {}
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Logging
# ──────────────────────────────────────────────────────────────────────────────

resource "google_logging_project_bucket_config" "app" {
  project        = var.project_id
  location       = var.location
  bucket_id      = "run-${local.prefix}"
  description    = "Cloud Run application logs for ${local.prefix}"
  retention_days = var.log_retention_days
}

# The filter matches the service name the cloudrun module derives from the
# same prefix. Same-project bucket destinations need no writer grant.
resource "google_logging_project_sink" "app" {
  project     = var.project_id
  name        = "sink-run-${local.prefix}"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.app.id}"

  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.prefix}\""

  unique_writer_identity = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Monitoring alert policies
# No notification channel is wired; the caller attaches routing out of band.
# ──────────────────────────────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "cpu_high" {
  project      = var.project_id
  display_name = "${local.prefix}-run-cpu-high"
  combiner     = "OR"

  documentation {
    content = "Cloud Run container CPU utilization above ${var.alert_cpu_threshold * 100}% for 2 minutes"
  }

  conditions {
    display_name = "Container CPU utilization (p99)"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/cpu/utilizations\" AND resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.prefix}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }

      # No datapoints (fresh deploy, scaled to zero) is not a breach.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  user_labels = local.base_labels
}

resource "google_monitoring_alert_policy" "memory_high" {
  project      = var.project_id
  display_name = "${local.prefix}-run-memory-high"
  combiner     = "OR"

  documentation {
    content = "Cloud Run container memory utilization above ${var.alert_memory_threshold * 100}% for 2 minutes"
  }

  conditions {
    display_name = "Container memory utilization (p99)"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.prefix}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }

      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  user_labels = local.base_labels
}

resource "google_monitoring_alert_policy" "instance_count_low" {
  project      = var.project_id
  display_name = "${local.prefix}-run-instance-count-low"
  combiner     = "OR"

  documentation {
    content = "Cloud Run running instance count dropped below ${var.alert_min_instance_count} for 2 minutes"
  }

  conditions {
    display_name = "Running instance count"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/instance_count\" AND resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.prefix}\""
      comparison      = "COMPARISON_LT"
      threshold_value = var.alert_min_instance_count
      duration        = "120s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
      }

      # No datapoints means nothing is running: that is the breach.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"
    }
  }

  user_labels = local.base_labels
}
