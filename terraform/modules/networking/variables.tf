variable "name" {
  description = "Base name for all resources (used as prefix; keep short — the Serverless VPC Access connector name has a 25-char limit, so only the first 12 chars of this value are used there)"
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
  description = "GCP region for regional resources (subnets, router, NAT, connector)"
  type        = string
}

variable "app_subnet_cidr" {
  description = "CIDR block for the app subnet. Use non-overlapping ranges per environment: dev=10.10.1.0/24, staging=10.20.1.0/24, prod=10.30.1.0/24"
  type        = string
  default     = "10.10.1.0/24"
}

variable "services_subnet_cidr" {
  description = "CIDR block for the services subnet (private backing services). dev=10.10.2.0/24, staging=10.20.2.0/24, prod=10.30.2.0/24"
  type        = string
  default     = "10.10.2.0/24"
}

variable "connector_cidr" {
  description = "CIDR block for the Serverless VPC Access connector subnet. Must be a /28. dev=10.10.8.0/28, staging=10.20.8.0/28, prod=10.30.8.0/28"
  type        = string
  default     = "10.10.8.0/28"
  validation {
    condition     = endswith(var.connector_cidr, "/28")
    error_message = "connector_cidr must be a /28 range — a Serverless VPC Access connector requires exactly a /28."
  }
}

variable "app_port" {
  description = "TCP port the application container listens on (used to scope the internal firewall rule)"
  type        = number
  default     = 8080
}

variable "flow_log_sampling" {
  description = "VPC flow log sampling rate as a decimal fraction (0.0–1.0). Applied to every subnet."
  type        = number
  default     = 0.5
  validation {
    condition     = var.flow_log_sampling > 0.0 && var.flow_log_sampling <= 1.0
    error_message = "flow_log_sampling must be between 0.0 (exclusive) and 1.0."
  }
}

variable "connector_min_instances" {
  description = "Minimum number of connector instances (GCP requires at least 2)"
  type        = number
  default     = 2
  validation {
    condition     = var.connector_min_instances >= 2
    error_message = "connector_min_instances must be at least 2 (GCP minimum)."
  }
}

variable "connector_max_instances" {
  description = "Maximum number of connector instances (must be greater than connector_min_instances)"
  type        = number
  default     = 3
}

variable "private_zone_domain" {
  description = "DNS name for the private managed zone, with trailing dot. Leave empty to derive <name>.<environment>.internal."
  type        = string
  default     = ""
}
