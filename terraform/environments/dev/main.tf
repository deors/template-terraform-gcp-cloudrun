locals {
  environment = "dev"

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

  log_retention_days = 30

  # Dev: sample every trace for full visibility during development
  enable_trace        = true
  trace_sampling_rate = 1.0
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

  # Dev range: 10.10.0.0/16 (non-overlapping with staging/prod)
  app_subnet_cidr        = "10.10.1.0/24"
  services_subnet_cidr   = "10.10.2.0/24"
  proxy_only_subnet_cidr = "10.10.4.0/23"
  connector_cidr         = "10.10.8.0/28"

  app_port = var.container_port

  # Dev's load balancer is external, so the app record goes in the public zone
  main_domain     = var.main_domain
  private_app_dns = false
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

  # Dev: 1 vCPU / 512Mi, fixed single instance, all traffic to the latest revision
  cpu                  = "1"
  memory               = "512Mi"
  min_instance_count   = 1
  max_instance_count   = 1
  enable_traffic_split = false

  # Dev: ingress all (run.app reachable from the internet, IAP in front);
  # with main_domain, an external load balancer also serves the custom domain
  internal         = false
  vpc_connector_id = module.networking.connector_id

  enable_trace   = module.monitoring.trace_enabled
  trace_env_vars = module.monitoring.trace_env_vars

  auth_members                     = var.auth_members
  auth_test_identity_impersonators = var.auth_test_identity_impersonators

  app_fqdn             = module.networking.app_fqdn
  network_id           = module.networking.network_id
  proxy_only_subnet_id = module.networking.proxy_only_subnet_id
  app_dns_zone_name    = module.networking.app_dns_zone_name
  public_dns_zone_name = module.networking.public_dns_zone_name
}
