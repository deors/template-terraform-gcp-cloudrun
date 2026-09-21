variable "name" {
  description = "Base name for all resources (used as prefix)"
  type        = string
}

variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Labels to apply to all resources. GCP label keys/values must be lowercase letters, numbers, hyphens and underscores."
  type        = map(string)
  default     = {}
}

variable "project_id" {
  description = "GCP project ID where all resources are created"
  type        = string
}

variable "location" {
  description = "Location for the Cloud Logging bucket (a region, or \"global\")"
  type        = string
  default     = "global"
}

variable "log_retention_days" {
  description = "Retention period in days for the Cloud Logging bucket (30, 60, or 90 per environment baseline)"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650
    error_message = "log_retention_days must be between 1 and 3650 days."
  }
}

variable "enable_trace" {
  description = "Enable Cloud Trace distributed tracing configuration for the Cloud Run service"
  type        = bool
  default     = true
}

variable "trace_sampling_rate" {
  description = "Trace sampling rate as a decimal fraction (0.0–1.0). dev=1.0, staging=0.10, prod=0.01. Enforced client-side; surfaced to the container through the trace_env_vars output."
  type        = number
  default     = 1.0
  validation {
    condition     = var.trace_sampling_rate >= 0.0 && var.trace_sampling_rate <= 1.0
    error_message = "trace_sampling_rate must be between 0.0 and 1.0."
  }
}

variable "alert_cpu_threshold" {
  description = "Cloud Run container CPU utilization threshold for the high-CPU alert, as a fraction (0.0–1.0)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.alert_cpu_threshold > 0.0 && var.alert_cpu_threshold <= 1.0
    error_message = "alert_cpu_threshold must be a fraction between 0.0 (exclusive) and 1.0."
  }
}

variable "alert_memory_threshold" {
  description = "Cloud Run container memory utilization threshold for the high-memory alert, as a fraction (0.0–1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.alert_memory_threshold > 0.0 && var.alert_memory_threshold <= 1.0
    error_message = "alert_memory_threshold must be a fraction between 0.0 (exclusive) and 1.0."
  }
}

variable "alert_min_instance_count" {
  description = "Minimum number of running Cloud Run instances below which the low-instance-count alert fires"
  type        = number
  default     = 1
}
