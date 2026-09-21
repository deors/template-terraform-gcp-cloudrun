locals {
  prefix = lower("${var.name}-${var.environment}")

  base_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "terraform"
    platform    = "platform-engineering"
  })

  # Connector names are capped at 25 chars: "vpcc-" + 12 + "-" + "staging".
  app_short      = trimsuffix(substr(lower(var.name), 0, 12), "-")
  connector_name = "vpcc-${local.app_short}-${var.environment}"

  private_zone_domain = var.private_zone_domain != "" ? var.private_zone_domain : "${lower(var.name)}.${var.environment}.internal."

  flow_log_config = {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC network and subnets
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "vpc-${local.prefix}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  project       = var.project_id
  name          = "snet-app-${local.prefix}"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.app_subnet_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = local.flow_log_config.aggregation_interval
    flow_sampling        = local.flow_log_config.flow_sampling
    metadata             = local.flow_log_config.metadata
  }
}

resource "google_compute_subnetwork" "services" {
  project       = var.project_id
  name          = "snet-services-${local.prefix}"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.services_subnet_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = local.flow_log_config.aggregation_interval
    flow_sampling        = local.flow_log_config.flow_sampling
    metadata             = local.flow_log_config.metadata
  }
}

# Dedicated /28 required by the Serverless VPC Access connector.
resource "google_compute_subnetwork" "connector" {
  project       = var.project_id
  name          = "snet-vpcc-${local.prefix}"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.connector_cidr

  private_ip_google_access = true

  log_config {
    aggregation_interval = local.flow_log_config.aggregation_interval
    flow_sampling        = local.flow_log_config.flow_sampling
    metadata             = local.flow_log_config.metadata
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Firewall
# Governs traffic entering the VPC from the connector and any backing services
# placed in the subnets; Cloud Run itself is not subject to VPC firewalls.
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_internal_app" {
  project = var.project_id
  name    = "fw-allow-internal-app-${local.prefix}"
  network = google_compute_network.this.id

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.connector_cidr, var.app_subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port), "443", "53"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Google Cloud Load Balancing health-check ranges.
resource "google_compute_firewall" "allow_lb_health_checks" {
  project = var.project_id
  name    = "fw-allow-lb-hc-${local.prefix}"
  network = google_compute_network.this.id

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Same effect as the implied deny, but logged.
resource "google_compute_firewall" "deny_all_ingress" {
  project = var.project_id
  name    = "fw-deny-all-ingress-${local.prefix}"
  network = google_compute_network.this.id

  direction     = "INGRESS"
  priority      = 65000
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Router + Cloud NAT
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "cr-${local.prefix}"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project = var.project_id
  name    = "nat-${local.prefix}"
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.services.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.connector.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud DNS private zone
# ──────────────────────────────────────────────────────────────────────────────

resource "google_dns_managed_zone" "private" {
  project     = var.project_id
  name        = "zone-${local.prefix}"
  dns_name    = local.private_zone_domain
  description = "Private zone for ${local.prefix} internal services"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }

  labels = local.base_labels
}

# ──────────────────────────────────────────────────────────────────────────────
# Serverless VPC Access connector
# ──────────────────────────────────────────────────────────────────────────────

resource "google_vpc_access_connector" "this" {
  project = var.project_id
  name    = local.connector_name
  region  = var.region

  subnet {
    name = google_compute_subnetwork.connector.name
  }

  min_instances = var.connector_min_instances
  max_instances = var.connector_max_instances
}
