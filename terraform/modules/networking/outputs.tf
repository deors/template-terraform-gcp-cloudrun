output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet role to subnet ID"
  value = {
    app       = google_compute_subnetwork.app.id
    services  = google_compute_subnetwork.services.id
    connector = google_compute_subnetwork.connector.id
  }
}

output "app_subnet_id" {
  description = "ID of the app subnet"
  value       = google_compute_subnetwork.app.id
}

output "services_subnet_id" {
  description = "ID of the services subnet"
  value       = google_compute_subnetwork.services.id
}

output "firewall_rule_ids" {
  description = "Map of firewall rule short names to their IDs"
  value = {
    allow_internal_app     = google_compute_firewall.allow_internal_app.id
    allow_lb_health_checks = google_compute_firewall.allow_lb_health_checks.id
    deny_all_ingress       = google_compute_firewall.deny_all_ingress.id
  }
}

output "connector_id" {
  description = "ID of the Serverless VPC Access connector (pass to the cloudrun module for VPC egress)"
  value       = google_vpc_access_connector.this.id
}

output "connector_name" {
  description = "Name of the Serverless VPC Access connector"
  value       = google_vpc_access_connector.this.name
}

output "private_zone_name" {
  description = "DNS name of the private managed zone (with trailing dot)"
  value       = google_dns_managed_zone.private.dns_name
}

output "private_zone_id" {
  description = "ID of the private managed zone"
  value       = google_dns_managed_zone.private.id
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway"
  value       = google_compute_router_nat.this.name
}

output "router_name" {
  description = "Name of the Cloud Router"
  value       = google_compute_router.this.name
}
