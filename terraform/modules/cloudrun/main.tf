locals {
  prefix = lower("${var.name}-${var.environment}")

  base_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "terraform"
    platform    = "platform-engineering"
  })

  # Service account IDs are capped at 30 chars: "run-" + 12 + "-" + "staging".
  app_short = trimsuffix(substr(lower(var.name), 0, 12), "-")

  project_number   = data.google_project.this.number
  serverless_agent = "service-${local.project_number}@serverless-robot-prod.iam.gserviceaccount.com"
  iap_agent        = "service-${local.project_number}@gcp-sa-iap.iam.gserviceaccount.com"
  registry_agent   = "service-${local.project_number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  docker_hub          = contains(["docker.io", "index.docker.io", "registry-1.docker.io"], var.container_registry_url)
  private_registry    = var.registry_credentials_secret_id != ""
  registry_secret     = startswith(var.registry_credentials_secret_id, "projects/") ? var.registry_credentials_secret_id : "projects/${var.project_id}/secrets/${var.registry_credentials_secret_id}"
  image_repository    = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
  plain_env           = merge(var.app_settings, var.trace_env_vars)
  referenced_secrets  = toset([for v in values(var.secret_env_vars) : v.secret_id])
  programmatic_access = var.auth_programmatic_client_id != ""

  custom_domain = var.app_fqdn != ""
  lb_scheme     = var.internal ? "INTERNAL_MANAGED" : "EXTERNAL_MANAGED"
}

data "google_project" "this" {
  project_id = var.project_id
}

# ──────────────────────────────────────────────────────────────────────────────
# Runtime identity
# ──────────────────────────────────────────────────────────────────────────────

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "run-${local.app_short}-${var.environment}"
  display_name = "Cloud Run runtime identity for ${local.prefix}"
}

resource "google_project_iam_member" "runtime" {
  for_each = toset(concat(
    ["roles/logging.logWriter", "roles/monitoring.metricWriter"],
    var.enable_trace ? ["roles/cloudtrace.agent"] : [],
  ))

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "runtime" {
  for_each = local.referenced_secrets

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Image repository (remote repository proxying container_registry_url)
# ──────────────────────────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "remote-${local.prefix}"
  description   = "Proxy of ${var.container_registry_url} for ${local.prefix}"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  labels        = local.base_labels

  remote_repository_config {
    description = var.container_registry_url

    docker_repository {
      public_repository = local.docker_hub ? "DOCKER_HUB" : null

      dynamic "custom_repository" {
        for_each = local.docker_hub ? [] : [1]
        content {
          uri = "https://${var.container_registry_url}"
        }
      }
    }

    dynamic "upstream_credentials" {
      for_each = local.private_registry ? [1] : []
      content {
        username_password_credentials {
          username                = var.registry_username
          password_secret_version = "${local.registry_secret}/versions/latest"
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !local.private_registry || var.registry_username != ""
      error_message = "registry_username is required when registry_credentials_secret_id is set."
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.registry]
}

resource "google_secret_manager_secret_iam_member" "registry" {
  count = local.private_registry ? 1 : 0

  project   = var.project_id
  secret_id = local.registry_secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.registry_agent}"
}

resource "google_artifact_registry_repository_iam_member" "serverless_agent" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${local.serverless_agent}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Run service
# ──────────────────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  name                = local.prefix
  location            = var.region
  ingress             = var.internal ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_ALL"
  iap_enabled         = true
  deletion_protection = var.deletion_protection
  labels              = local.base_labels

  template {
    service_account = google_service_account.runtime.email
    labels          = local.base_labels

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = "${local.image_repository}/${var.container_image}"

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = local.plain_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env_vars
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = env.value.version
            }
          }
        }
      }

      startup_probe {
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 12
        http_get {
          path = var.health_check_path
          port = var.container_port
        }
      }

      liveness_probe {
        period_seconds    = 30
        timeout_seconds   = 5
        failure_threshold = 3
        http_get {
          path = var.health_check_path
          port = var.container_port
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # Revisions deployed by the application's CI/CD survive reconcile runs.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
      template[0].revision,
      traffic,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_iam_member.runtime,
    google_secret_manager_secret_iam_member.runtime,
    google_artifact_registry_repository_iam_member.serverless_agent,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Authentication (IAP on the service covers run.app and load balancer traffic)
# ──────────────────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service_iam_member" "iap_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.iap_agent}"
}

resource "google_iap_web_cloud_run_service_iam_member" "members" {
  for_each = toset(var.auth_members)

  project                = var.project_id
  location               = var.region
  cloud_run_service_name = google_cloud_run_v2_service.this.name
  role                   = "roles/iap.httpsResourceAccessor"
  member                 = each.value
}

resource "google_service_account" "test_identity" {
  project      = var.project_id
  account_id   = "e2e-${local.app_short}-${var.environment}"
  display_name = "End-to-end test identity for ${local.prefix}"
}

resource "google_iap_web_cloud_run_service_iam_member" "test_identity" {
  project                = var.project_id
  location               = var.region
  cloud_run_service_name = google_cloud_run_v2_service.this.name
  role                   = "roles/iap.httpsResourceAccessor"
  member                 = "serviceAccount:${google_service_account.test_identity.email}"
}

resource "google_service_account_iam_member" "test_identity_token_creator" {
  for_each = toset(var.auth_test_identity_impersonators)

  service_account_id = google_service_account.test_identity.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_iap_settings" "this" {
  count = local.programmatic_access ? 1 : 0

  name = "projects/${local.project_number}/iap_web/cloud_run-${var.region}/services/${google_cloud_run_v2_service.this.name}"

  access_settings {
    oauth_settings {
      programmatic_clients = [var.auth_programmatic_client_id]
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Custom domain: regional Application Load Balancer, certificate and DNS
# ──────────────────────────────────────────────────────────────────────────────

resource "terraform_data" "lb_prerequisites" {
  count = local.custom_domain ? 1 : 0

  input = var.proxy_only_subnet_id

  lifecycle {
    precondition {
      condition = alltrue([
        var.network_id != "",
        var.proxy_only_subnet_id != "",
        var.app_dns_zone_name != "",
        var.public_dns_zone_name != "",
        !var.internal || var.lb_subnet_id != "",
      ])
      error_message = "app_fqdn requires network_id, proxy_only_subnet_id, app_dns_zone_name and public_dns_zone_name, plus lb_subnet_id when internal is true."
    }
  }
}

resource "google_compute_region_network_endpoint_group" "this" {
  count = local.custom_domain ? 1 : 0

  project               = var.project_id
  name                  = "neg-${local.prefix}"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.this.name
  }
}

resource "google_compute_region_backend_service" "this" {
  count = local.custom_domain ? 1 : 0

  project               = var.project_id
  name                  = "bes-${local.prefix}"
  region                = var.region
  load_balancing_scheme = local.lb_scheme
  protocol              = "HTTPS"

  backend {
    group           = google_compute_region_network_endpoint_group.this[0].id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_region_url_map" "https" {
  count = local.custom_domain ? 1 : 0

  project         = var.project_id
  name            = "um-${local.prefix}"
  region          = var.region
  default_service = google_compute_region_backend_service.this[0].id
}

resource "google_compute_region_url_map" "redirect" {
  count = local.custom_domain ? 1 : 0

  project = var.project_id
  name    = "um-redirect-${local.prefix}"
  region  = var.region

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# RESTRICTED profile with a TLS 1.2 floor; TLS 1.3 is negotiated when the client supports it.
resource "google_compute_region_ssl_policy" "this" {
  count = local.custom_domain ? 1 : 0

  project         = var.project_id
  name            = "ssl-${local.prefix}"
  region          = var.region
  profile         = "RESTRICTED"
  min_tls_version = "TLS_1_2"
}

resource "google_certificate_manager_dns_authorization" "this" {
  count = local.custom_domain ? 1 : 0

  project  = var.project_id
  name     = "dnsauth-${local.prefix}"
  location = var.region
  domain   = var.app_fqdn
  type     = "PER_PROJECT_RECORD"
  labels   = local.base_labels
}

resource "google_dns_record_set" "dns_authorization" {
  count = local.custom_domain ? 1 : 0

  project      = var.project_id
  managed_zone = var.public_dns_zone_name
  name         = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "this" {
  count = local.custom_domain ? 1 : 0

  project  = var.project_id
  name     = "cert-${local.prefix}"
  location = var.region
  labels   = local.base_labels

  managed {
    domains            = [var.app_fqdn]
    dns_authorizations = [google_certificate_manager_dns_authorization.this[0].id]
  }
}

resource "google_compute_region_target_https_proxy" "this" {
  count = local.custom_domain ? 1 : 0

  project                          = var.project_id
  name                             = "thps-${local.prefix}"
  region                           = var.region
  url_map                          = google_compute_region_url_map.https[0].id
  certificate_manager_certificates = [google_certificate_manager_certificate.this[0].id]
  ssl_policy                       = google_compute_region_ssl_policy.this[0].id
}

resource "google_compute_region_target_http_proxy" "redirect" {
  count = local.custom_domain ? 1 : 0

  project = var.project_id
  name    = "thp-${local.prefix}"
  region  = var.region
  url_map = google_compute_region_url_map.redirect[0].id
}

# Shared by the HTTPS and HTTP forwarding rules.
resource "google_compute_address" "lb" {
  count = local.custom_domain ? 1 : 0

  project      = var.project_id
  name         = "ip-${local.prefix}"
  region       = var.region
  address_type = var.internal ? "INTERNAL" : "EXTERNAL"
  subnetwork   = var.internal ? var.lb_subnet_id : null
  purpose      = var.internal ? "SHARED_LOADBALANCER_VIP" : null
  network_tier = var.internal ? null : "STANDARD"
  labels       = local.base_labels
}

resource "google_compute_forwarding_rule" "https" {
  count = local.custom_domain ? 1 : 0

  project               = var.project_id
  name                  = "fr-https-${local.prefix}"
  region                = var.region
  load_balancing_scheme = local.lb_scheme
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = google_compute_address.lb[0].id
  target                = google_compute_region_target_https_proxy.this[0].id
  network               = var.network_id
  subnetwork            = var.internal ? var.lb_subnet_id : null
  network_tier          = var.internal ? null : "STANDARD"
  labels                = local.base_labels

  depends_on = [terraform_data.lb_prerequisites]
}

resource "google_compute_forwarding_rule" "http" {
  count = local.custom_domain ? 1 : 0

  project               = var.project_id
  name                  = "fr-http-${local.prefix}"
  region                = var.region
  load_balancing_scheme = local.lb_scheme
  ip_protocol           = "TCP"
  port_range            = "80"
  ip_address            = google_compute_address.lb[0].id
  target                = google_compute_region_target_http_proxy.redirect[0].id
  network               = var.network_id
  subnetwork            = var.internal ? var.lb_subnet_id : null
  network_tier          = var.internal ? null : "STANDARD"
  labels                = local.base_labels

  depends_on = [terraform_data.lb_prerequisites]
}

resource "google_dns_record_set" "app" {
  count = local.custom_domain ? 1 : 0

  project      = var.project_id
  managed_zone = var.app_dns_zone_name
  name         = "${var.app_fqdn}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.lb[0].address]
}
