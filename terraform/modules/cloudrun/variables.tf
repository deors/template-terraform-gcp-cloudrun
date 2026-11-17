variable "name" {
  description = "Base name for all resources (used as prefix; the service is named <name>-<environment>, and service account IDs use only the first 12 chars of this value)"
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
  description = "Labels to apply to all resources that support them"
  type        = map(string)
  default     = {}
}

variable "project_id" {
  description = "GCP project ID where all resources are created"
  type        = string
}

variable "region" {
  description = "GCP region for the service, the image repository and the load balancer"
  type        = string
}

# ──────────────────────────────────────────────────────────────────────────────
# Container
# ──────────────────────────────────────────────────────────────────────────────

variable "container_registry_url" {
  description = "Registry host the container image comes from (e.g. ghcr.io, docker.io). Images are pulled through an Artifact Registry remote repository that proxies this registry."
  type        = string
  default     = "ghcr.io"
}

variable "container_image" {
  description = "Container image path and tag without the registry host (e.g. owner/app:latest)"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on. Cloud Run injects it as PORT and the probes use it."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for the startup and liveness probes"
  type        = string
  default     = "/health"
}

variable "app_settings" {
  description = "Plain environment variables for the container. Must not include PORT (injected from container_port)."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.app_settings), "PORT")
    error_message = "app_settings must not set PORT; Cloud Run injects it from container_port."
  }
}

variable "secret_env_vars" {
  description = "Environment variables sourced from Secret Manager: map of variable name to { secret_id (short name or projects/<p>/secrets/<s>), version (default latest) }. The runtime service account gets accessor rights on each secret."
  type = map(object({
    secret_id = string
    version   = optional(string, "latest")
  }))
  default = {}
  validation {
    condition     = !contains(keys(var.secret_env_vars), "PORT")
    error_message = "secret_env_vars must not set PORT; Cloud Run injects it from container_port."
  }
}

variable "registry_credentials_secret_id" {
  description = "Secret Manager secret (short name or projects/<p>/secrets/<s>) holding the password or token for a private upstream registry. Leave empty for public images."
  type        = string
  default     = ""
}

variable "registry_username" {
  description = "Username for the private upstream registry. Required when registry_credentials_secret_id is set."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU limit per instance (e.g. 1, 2)"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance (e.g. 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
}

# ──────────────────────────────────────────────────────────────────────────────
# Scaling and rollout
# ──────────────────────────────────────────────────────────────────────────────

variable "min_instance_count" {
  description = "Minimum number of instances (0 allows scale to zero)"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must be 0 or greater."
  }
}

variable "max_instance_count" {
  description = "Maximum number of instances"
  type        = number
  default     = 3
  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count >= var.min_instance_count
    error_message = "max_instance_count must be at least 1 and not lower than min_instance_count."
  }
}

variable "enable_traffic_split" {
  description = "Whether the application's CI/CD deploys new revisions without traffic and shifts it gradually (true) or routes all traffic to the latest revision on deploy (false). Exposed as an output for the deployment workflow."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent OpenTofu from destroying the service"
  type        = bool
  default     = false
}

# ──────────────────────────────────────────────────────────────────────────────
# Network and observability
# ──────────────────────────────────────────────────────────────────────────────

variable "internal" {
  description = "Keep the service off the internet: ingress internal-and-cloud-load-balancing and, with app_fqdn set, an internal load balancer (staging, prod). False gives ingress all and an external load balancer (dev)."
  type        = bool
  default     = true
}

variable "vpc_connector_id" {
  description = "ID of the Serverless VPC Access connector; all egress goes through it"
  type        = string
}

variable "enable_trace" {
  description = "Grant the runtime service account the Cloud Trace agent role"
  type        = bool
  default     = true
}

variable "trace_env_vars" {
  description = "Trace sampling environment variables for the container (the monitoring module's trace_env_vars output)"
  type        = map(string)
  default     = {}
}

# ──────────────────────────────────────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────────────────────────────────────

variable "auth_members" {
  description = "Principals allowed through IAP, in IAM member format (user:alice@example.com, group:team@example.com)"
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for m in var.auth_members : can(regex("^(user|group|serviceAccount|domain|principal|principalSet):", m))])
    error_message = "auth_members entries must use IAM member format, e.g. user:alice@example.com or group:team@example.com."
  }
}

variable "auth_test_identity_impersonators" {
  description = "Principals (IAM member format) allowed to sign JWTs as the test identity, e.g. the CI/CD service account"
  type        = list(string)
  default     = []
}

# ──────────────────────────────────────────────────────────────────────────────
# Custom domain (all empty when main_domain is not used)
# ──────────────────────────────────────────────────────────────────────────────

variable "app_fqdn" {
  description = "Application FQDN served through the load balancer (networking module app_fqdn output). Empty disables the load balancer, certificate and DNS records."
  type        = string
  default     = ""
  nullable    = false
}

variable "network_id" {
  description = "ID of the VPC network for the load balancer. Required when app_fqdn is set."
  type        = string
  default     = ""
  nullable    = false
}

variable "lb_subnet_id" {
  description = "Subnet for the internal load balancer IP address. Required when app_fqdn is set and internal is true."
  type        = string
  default     = ""
  nullable    = false
}

variable "proxy_only_subnet_id" {
  description = "ID of the proxy-only subnet (networking module output); the load balancer is created after it. Required when app_fqdn is set."
  type        = string
  default     = ""
  nullable    = false
}

variable "app_dns_zone_name" {
  description = "Cloud DNS zone for the application A record (networking module app_dns_zone_name output). Required when app_fqdn is set."
  type        = string
  default     = ""
  nullable    = false
}

variable "public_dns_zone_name" {
  description = "Public Cloud DNS zone for the certificate DNS authorization record (networking module public_dns_zone_name output). Required when app_fqdn is set."
  type        = string
  default     = ""
  nullable    = false
}
