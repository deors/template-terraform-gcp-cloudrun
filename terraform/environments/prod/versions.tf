terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # All backend values are injected at init time via -backend-config flags.
  # The bucket must already exist: run the state bootstrap from
  # workshop-platform-eng first (cross-cutting concern, not owned by this repo).
  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  default_labels = {
    application = var.app_name
    environment = "prod"
    managed-by  = "opentofu"
    platform    = "platform-engineering"
  }
}
