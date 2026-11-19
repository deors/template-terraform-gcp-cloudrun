variable "gcp_project_id" {
  description = "GCP project ID for all resources. No default — must be set explicitly to avoid deploying into the wrong project."
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all regional resources (e.g. europe-west1). No default — must be set explicitly to avoid accidental cross-region deployments."
  type        = string
}

variable "app_name" {
  description = "Application name: 3-30 chars, lowercase letters, digits and hyphens, starting with a letter. Used as a resource name prefix and as the application label."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-30 chars of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "container_image" {
  description = "Container image path and tag without the registry host (e.g. owner/app:latest)"
  type        = string
}

variable "container_registry_url" {
  description = "Registry host the image is pulled from, through an Artifact Registry remote repository (e.g. ghcr.io, docker.io)"
  type        = string
  default     = "ghcr.io"
}

variable "registry_credentials_secret_id" {
  description = "Secret Manager secret holding the password or token of a private upstream registry; empty for public images"
  type        = string
  default     = ""
}

variable "registry_username" {
  description = "Username for the private upstream registry; required when registry_credentials_secret_id is set"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "TCP port the application container listens on; Cloud Run injects it as PORT"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for the startup and liveness probes"
  type        = string
  default     = "/health"
}

variable "main_domain" {
  description = "Root domain with a public Cloud DNS zone in the project (e.g. \"example.com\"). When set, the app is also served at <app_name>.prod.<main_domain> through an internal load balancer, resolvable only inside the VPC. Empty for the run.app URL only, which is reachable only from inside the VPC as well."
  type        = string
}

variable "app_settings" {
  description = "Additional application environment variables (must not include PORT)"
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = "Environment variables sourced from Secret Manager: map of variable name to { secret_id, version (default latest) }"
  type = map(object({
    secret_id = string
    version   = optional(string, "latest")
  }))
  default = {}
}

variable "auth_members" {
  description = "Principals allowed through IAP, in IAM member format (user:alice@example.com, group:team@example.com)"
  type        = list(string)
  default     = []
}

variable "auth_test_identity_impersonators" {
  description = "Principals (IAM member format) allowed to sign JWTs as the end-to-end test identity, e.g. the CI/CD service account"
  type        = list(string)
  default     = []
}
