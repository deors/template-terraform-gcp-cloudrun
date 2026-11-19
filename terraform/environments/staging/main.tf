locals {
  environment = "staging"

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

  log_retention_days = 60

  # Staging: sample 10% of traces
  enable_trace        = true
  trace_sampling_rate = 0.1
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

  # Staging range: 10.20.0.0/16 (non-overlapping with dev/prod)
  app_subnet_cidr        = "10.20.1.0/24"
  services_subnet_cidr   = "10.20.2.0/24"
  proxy_only_subnet_cidr = "10.20.4.0/23"
  connector_cidr         = "10.20.8.0/28"

  app_port = var.container_port

  # Staging's load balancer is internal, so the app record goes in a VPC-private zone
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

  # Staging: 1 vCPU / 1Gi, 1-3 instances, gradual traffic shifting on deploy
  cpu                  = "1"
  memory               = "1Gi"
  min_instance_count   = 1
  max_instance_count   = 3
  enable_traffic_split = true

  # Staging: ingress internal load balancing only (run.app reachable from the
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
