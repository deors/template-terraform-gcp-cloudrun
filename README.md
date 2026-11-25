# template-terraform-gcp-cloudrun

A **GitHub template repository** — the infrastructure-as-code archetype for provisioning secure, observable GCP infrastructure for containerised web applications.

When used with the **workshop-platform-eng** provisioning workflow:

1. The platform creates a new repository from this template, named `{app-name}-infra`.
2. The platform runs `terraform plan` and `terraform apply` against this infrastructure code.
3. The provisioned infrastructure (Cloud Run services, VPC, Private Endpoint, Load Balancer, autoscale, etc.) is deployed across `dev`, `staging`, `prod` environments.

---

## Infrastructure Architecture

| Component | Description | Environment-Specific |
|-----------|-------------|----------------------|

**TBC**

---

## Module Structure

``` text
terraform/
├── environments/
│   ├── dev/           # Development environment (**TBC**)
│   ├── staging/       # Staging environment (**TBC**)
│   └── prod/          # Production environment (**TBC**)
│
└── modules/
    ├── monitoring/    # **TBC**
    ├── networking/    # **TBC**
    └── cloudrun/      # **TBC**

scripts/
└── verify.sh          # Post-apply control-plane verification (see below)
```

---

## Verification

This template owns its own post-apply verification at the canonical path
`scripts/verify.sh`. After `terraform apply`, the **workshop-platform-eng**
orchestrator checks out the generated `{app-name}-infra` repository and runs
this script, then surfaces the pass/fail counts. Because the assertions live
next to the Terraform that defines the expectations (**TBC**, …), the orchestrator stays template-agnostic:
any infra template that exposes `scripts/verify.sh` plugs in without changing
the platform.

The script requires `APP_NAME`, `ENVIRONMENT` (`dev`/`staging`/`prod`),
`GCP_PROJECT` and `GCP_REGION` (no fallback to the ambient gcloud
configuration); `MAIN_DOMAIN` is optional and adds the certificate and DNS
checks. It uses `gcloud` and `jq` only. Exit codes: `0` all checks passed, `1`
at least one failed, `2` invalid invocation. Every exit path writes
`/tmp/verify-summary.txt` (override with `VERIFY_SUMMARY_FILE`) with
`environment=`, `passed=` and `failed=` lines, and appends a markdown summary to
`GITHUB_STEP_SUMMARY` when set. To run it locally against a deployed
environment (a `gcloud auth login` session must be active):

```bash
APP_NAME=<app> ENVIRONMENT=<env> GCP_PROJECT=<project> GCP_REGION=<region> bash scripts/verify.sh
```

---

## Environment-Specific Baselines

### Development (`dev/`)

- **Compute**: **TBC**
- **Instances**: **TBC**
- **Availability**: **TBC**
- **Networking**: **TBC**
- **Log Retention**: **TBC**
- **Checkov Baseline**: **TBC**

### Staging (`staging/`)

- **Compute**: **TBC**
- **Instances**: **TBC**
- **Availability**: **TBC**
- **Networking**: **TBC**
- **Log Retention**: **TBC**
- **Checkov Baseline**: **TBC**

### Production (`prod/`)

- **Compute**: **TBC**
- **Instances**: **TBC**
- **Availability**: **TBC**
- **Networking**: **TBC**
- **Log Retention**: **TBC**
- **Checkov Baseline**: **TBC**

---

## Security & Compliance

### Network Isolation

- **Egress**: **TBC** restrict outbound to GCP services (HTTPS 443, DNS 53) only
- **Inbound**: **TBC** Private Endpoint + optional IP restrictions on public endpoint (dev only)
- **Flow Logs**: **TBC** Network traffic diagnostics logged to dedicate storage for compliance audit trails

### Identity & Access

- **Managed Identity**: **TBC**
- **RBAC**: **TBC**
- **TLS**: Minimum 1.3 enforced on production; 1.2 or 1.3 in dev/staging

### Compliance

- **Checkov**: Infrastructure security policy enforcement with environment-specific baselines (prod strict, dev/staging relaxed)
- **Diagnostics**: Comprehensive logging to **TBC** (HTTP logs, console logs, audit logs, platform logs)
- **Encryption**: End-to-end TLS encryption (enabled **TBC**)

---

## Customization

### App Settings

App-specific environment variables are passed via `app_settings` map in each environment's `.tfvars`. Example:

```hcl
app_settings = {
  DATABASE_URL = "postgresql://..."
  API_KEY      = "..."
}
```

### Custom Domain

Production supports custom domain binding with managed certificate:

```hcl
custom_domain = "myapp.example.com"
managed_certificate = true
```

### Container Registry

Pull images from private container registry (GHCR, ACR, Docker Hub):

```hcl
container_registry_url = "**TBC**"
container_image        = "**TBC**"
```

### Secret Management Integration

Optional integration for storing & referencing secrets:

```hcl
**TBC**
```

---

## Terraform Workflow

### 1. Bootstrap Terraform State (one-time)

```bash
./scripts/bootstrap-tfstate.sh \
  --app-name myapp \
  **TBC** \
  **TBC**
```

Creates a dedicated GCS bucket for remote state (idempotent).

### 2. Plan

```bash
cd terraform/environments/dev
terraform init \
  -backend-config="**TBC**" \
  -backend-config="**TBC**" \
  -backend-config="**TBC**"
terraform plan -var-file="terraform.tfvars"
```

### 3. Apply

```bash
terraform apply tfplan
```

---

## License

[MIT](LICENSE) — see the license file for details.
