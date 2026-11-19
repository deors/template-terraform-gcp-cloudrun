locals {
  environment = "prod"

  common_labels = {
    application = var.app_name
    environment = local.environment
    managed-by  = "opentofu"
    platform    = "platform-engineering"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Monitoring (Cloud Logging bucket, alert policies, trace sampling)
# ──────────────────────────────────────────────────────────────────────────────
module "monitoring" {
  source = "../../modules/monitoring"

  name        = var.app_name
  environment = local.environment
  labels      = local.common_labels
  project_id  = var.gcp_project_id

  log_retention_days = 90

  # Prod: sample 1% of traces
  enable_trace        = true
  trace_sampling_rate = 0.01
}

# ──────────────────────────────────────────────────────────────────────────────
# Networking (VPC, subnets, firewall, Cloud NAT, connector, Cloud DNS)
# ──────────────────────────────────────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  name        = var.app_name
  environment = local.environment
  labels      = local.common_labels
  project_id  = var.gcp_project_id
  region      = var.gcp_region

  # Prod range: 10.30.0.0/16 (non-overlapping with dev/staging)
  app_subnet_cidr        = "10.30.1.0/24"
  services_subnet_cidr   = "10.30.2.0/24"
  proxy_only_subnet_cidr = "10.30.4.0/23"
  connector_cidr         = "10.30.8.0/28"

  app_port = var.container_port

  # Prod's load balancer is internal, so the app record goes in a VPC-private zone
  main_domain     = var.main_domain
  private_app_dns = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Run (service, runtime identity, IAP, image repository, load balancer)
# ──────────────────────────────────────────────────────────────────────────────
module "cloudrun" {
  source = "../../modules/cloudrun"

  name        = var.app_name
  environment = local.environment
  labels      = local.common_labels
  project_id  = var.gcp_project_id
  region      = var.gcp_region

  container_registry_url         = var.container_registry_url
  container_image                = var.container_image
  registry_credentials_secret_id = var.registry_credentials_secret_id
  registry_username              = var.registry_username
  container_port                 = var.container_port
  health_check_path              = var.health_check_path
  app_settings                   = var.app_settings
  secret_env_vars                = var.secret_env_vars

  # Prod: 2 vCPU / 2Gi, 3-10 instances spread across the region's zones,
  # gradual traffic shifting on deploy
  cpu                  = "2"
  memory               = "2Gi"
  min_instance_count   = 3
  max_instance_count   = 10
  enable_traffic_split = true

  # Prod: ingress internal load balancing only (run.app reachable from the
  # VPC, IAP in front); with main_domain, an internal load balancer serves the
  # custom domain
  internal         = true
  vpc_connector_id = module.networking.connector_id

  enable_trace   = module.monitoring.trace_enabled
  trace_env_vars = module.monitoring.trace_env_vars

  auth_members                     = var.auth_members
  auth_test_identity_impersonators = var.auth_test_identity_impersonators

  app_fqdn             = module.networking.app_fqdn
  network_id           = module.networking.network_id
  lb_subnet_id         = module.networking.app_subnet_id
  proxy_only_subnet_id = module.networking.proxy_only_subnet_id
  app_dns_zone_name    = module.networking.app_dns_zone_name
  public_dns_zone_name = module.networking.public_dns_zone_name
}
