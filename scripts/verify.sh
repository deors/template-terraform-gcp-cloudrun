#!/usr/bin/env bash
#
# Post-apply verification for the Cloud Run infrastructure template.
#
# Required env: APP_NAME, ENVIRONMENT (dev|staging|prod), GCP_PROJECT, GCP_REGION
# Optional env: MAIN_DOMAIN       adds the certificate and DNS checks
#               VERIFY_SUMMARY_FILE   summary file (default /tmp/verify-summary.txt)
#               VERIFY_WAIT_SECONDS   first-deployment convergence wait (default 300)
#               GITHUB_STEP_SUMMARY   when set, a markdown summary is appended
#
# Exit codes: 0 all checks passed, 1 at least one check failed,
#             2 invalid invocation (no checks ran).
# Requires gcloud and jq only; compatible with bash 3.2.

SUMMARY_FILE="${VERIFY_SUMMARY_FILE:-/tmp/verify-summary.txt}"
WAIT_SECONDS="${VERIFY_WAIT_SECONDS:-300}"
WAIT_INTERVAL=10

PASSED=0
FAILED=0
RESULTS=""
SUMMARY_WRITTEN=0
NL='
'

write_summary() {
  [ "$SUMMARY_WRITTEN" = 1 ] && return 0
  SUMMARY_WRITTEN=1
  {
    echo "environment=${ENVIRONMENT:-}"
    echo "passed=${PASSED}"
    echo "failed=${FAILED}"
  } > "$SUMMARY_FILE" 2>/dev/null
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Infrastructure verification (${ENVIRONMENT:-unknown})"
      echo
      echo "| Result | Passed | Failed |"
      echo "|--------|--------|--------|"
      echo "| $([ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ] && echo ':white_check_mark:' || echo ':x:') | ${PASSED} | ${FAILED} |"
      if [ -n "$RESULTS" ]; then
        echo
        printf '%s' "$RESULTS"
      fi
    } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null
  fi
  return 0
}

# Every exit path (including unexpected ones) writes the summary.
# shellcheck disable=SC2154
trap 'rc=$?; write_summary; exit $rc' EXIT

invalid() {
  echo "ERROR: $*" >&2
  exit 2
}

pass() {
  PASSED=$((PASSED + 1))
  echo "PASS: $1"
  RESULTS="${RESULTS}- :white_check_mark: ${1}${NL}"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL: $1${2:+ ($2)}"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error title=Verification failed::$1${2:+ ($2)}"
  fi
  RESULTS="${RESULTS}- :x: ${1}${2:+ (${2})}${NL}"
}

# check "description" "detail on failure" <command...>  (passes when command succeeds)
check() {
  local desc="$1" detail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc" "$detail"; fi
}

# eq "description" actual expected
eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$3', got '${2:-<none>}'"; fi
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Invocation validation ────────────────────────────────────────────────────
[ -n "${APP_NAME:-}" ] || invalid "APP_NAME is required"
[ -n "${ENVIRONMENT:-}" ] || invalid "ENVIRONMENT is required"
[ -n "${GCP_PROJECT:-}" ] || invalid "GCP_PROJECT is required"
[ -n "${GCP_REGION:-}" ] || invalid "GCP_REGION is required"
case "$ENVIRONMENT" in
  dev | staging | prod) ;;
  *) invalid "ENVIRONMENT must be one of dev, staging, prod (got '$ENVIRONMENT')" ;;
esac
case "$WAIT_SECONDS" in
  '' | *[!0-9]*) invalid "VERIFY_WAIT_SECONDS must be a non-negative integer" ;;
esac
command -v gcloud >/dev/null 2>&1 || invalid "gcloud is required"
command -v jq >/dev/null 2>&1 || invalid "jq is required"

# ── Expectations per environment (mirrors terraform/environments/*/main.tf) ──
LOG_RETENTION_DAYS=30
case "$ENVIRONMENT" in
  dev)
    EXPECT_INGRESS="all"
    EXPECT_CPU="1"; EXPECT_MEMORY="512Mi"; EXPECT_MIN="1"; EXPECT_MAX="1"
    EXPECT_LB_SCHEME="EXTERNAL_MANAGED"
    LOG_RETENTION_DAYS=30
    ;;
  staging)
    EXPECT_INGRESS="internal-and-cloud-load-balancing"
    EXPECT_CPU="1"; EXPECT_MEMORY="1Gi"; EXPECT_MIN="1"; EXPECT_MAX="3"
    EXPECT_LB_SCHEME="INTERNAL_MANAGED"
    LOG_RETENTION_DAYS=60
    ;;
  prod)
    EXPECT_INGRESS="internal-and-cloud-load-balancing"
    EXPECT_CPU="2"; EXPECT_MEMORY="2Gi"; EXPECT_MIN="3"; EXPECT_MAX="10"
    EXPECT_LB_SCHEME="INTERNAL_MANAGED"
    LOG_RETENTION_DAYS=90
    ;;
esac

APP_LOWER="$(lower "$APP_NAME")"
PREFIX="${APP_LOWER}-${ENVIRONMENT}"
APP_SHORT="$(printf '%s' "$APP_LOWER" | cut -c1-12)"
APP_SHORT="${APP_SHORT%-}"
PROJECT="$GCP_PROJECT"
REGION="$GCP_REGION"
SERVICE="$PREFIX"
TEST_IDENTITY="e2e-${APP_SHORT}-${ENVIRONMENT}@${PROJECT}.iam.gserviceaccount.com"
CONNECTOR="vpcc-${APP_SHORT}-${ENVIRONMENT}"
MAIN_DOMAIN="${MAIN_DOMAIN:-}"
MAIN_DOMAIN="${MAIN_DOMAIN%.}"
APP_FQDN=""
[ -n "$MAIN_DOMAIN" ] && APP_FQDN="${APP_LOWER}.${ENVIRONMENT}.${MAIN_DOMAIN}"

# gcloud wrapper: never relies on the ambient project, no prompts
gc() { gcloud "$@" --project="$PROJECT" --quiet; }

echo "Verifying ${PREFIX} in ${PROJECT}/${REGION}"

# ── Cloud Run service and revision readiness ─────────────────────────────────
svc_json() { gc run services describe "$SERVICE" --region="$REGION" --format=json 2>/dev/null; }

ready_state() {
  # prints "ok" once service Ready and latest created revision is latest ready
  printf '%s' "$1" | jq -r '
    if ((.status.conditions // []) | map(select(.type == "Ready" and .status == "True")) | length) > 0
       and (.status.latestReadyRevisionName // "") != ""
       and .status.latestReadyRevisionName == .status.latestCreatedRevisionName
    then "ok" else "wait" end' 2>/dev/null
}

SVC=""
waited=0
while :; do
  SVC="$(svc_json)"
  if [ -n "$SVC" ] && [ "$(ready_state "$SVC")" = "ok" ]; then break; fi
  if [ "$waited" -ge "$WAIT_SECONDS" ]; then break; fi
  sleep "$WAIT_INTERVAL"
  waited=$((waited + WAIT_INTERVAL))
done

if [ -z "$SVC" ]; then
  fail "Cloud Run service ${SERVICE} exists" "describe failed"
  SVC='{}'
else
  pass "Cloud Run service ${SERVICE} exists"
fi

jqs() { printf '%s' "$SVC" | jq -r "$1" 2>/dev/null; }

eq "Cloud Run service Ready condition is True" \
  "$(jqs '[.status.conditions[]? | select(.type=="Ready") | .status] | first // ""')" "True"
LATEST_CREATED="$(jqs '.status.latestCreatedRevisionName // ""')"
LATEST_READY="$(jqs '.status.latestReadyRevisionName // ""')"
if [ -n "$LATEST_CREATED" ] && [ "$LATEST_CREATED" = "$LATEST_READY" ]; then
  pass "Latest created revision ${LATEST_CREATED} is the latest ready revision"
else
  fail "Latest created revision is the latest ready revision" "created='${LATEST_CREATED}' ready='${LATEST_READY}'"
fi
if [ -n "$LATEST_CREATED" ]; then
  REV_READY="$(gc run revisions describe "$LATEST_CREATED" --region="$REGION" --format=json 2>/dev/null |
    jq -r '[.status.conditions[]? | select(.type=="Ready") | .status] | first // ""' 2>/dev/null)"
  eq "Latest revision Ready condition is True" "$REV_READY" "True"
else
  fail "Latest revision Ready condition is True" "no revision"
fi

# ── Authentication ───────────────────────────────────────────────────────────
eq "IAP enabled on the service" "$(jqs '.metadata.annotations["run.googleapis.com/iap-enabled"] // ""')" "true"

PROJECT_NUMBER="$(gc projects describe "$PROJECT" --format='value(projectNumber)' 2>/dev/null)"
IAP_AGENT="service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com"
RUN_IAM="$(gc run services get-iam-policy "$SERVICE" --region="$REGION" --format=json 2>/dev/null)"
[ -n "$RUN_IAM" ] || RUN_IAM='{}'
if [ -n "$PROJECT_NUMBER" ] && printf '%s' "$RUN_IAM" | jq -e --arg m "serviceAccount:${IAP_AGENT}" \
  '[.bindings[]? | select(.role=="roles/run.invoker") | .members[]?] | index($m) != null' >/dev/null 2>&1; then
  pass "IAP service agent is a Cloud Run invoker"
else
  fail "IAP service agent is a Cloud Run invoker" "${IAP_AGENT}"
fi
if printf '%s' "$RUN_IAM" | jq -e \
  '[.bindings[]?.members[]?] | map(select(. == "allUsers" or . == "allAuthenticatedUsers")) | length == 0' >/dev/null 2>&1; then
  pass "allUsers / allAuthenticatedUsers absent from Cloud Run IAM policy"
else
  fail "allUsers / allAuthenticatedUsers absent from Cloud Run IAM policy" "public binding present"
fi

IAP_IAM="$(gc iap web get-iam-policy --resource-type=cloud-run --service="$SERVICE" --region="$REGION" --format=json 2>/dev/null)"
[ -n "$IAP_IAM" ] || IAP_IAM='{}'
if printf '%s' "$IAP_IAM" | jq -e --arg m "serviceAccount:${TEST_IDENTITY}" \
  '[.bindings[]? | select(.role=="roles/iap.httpsResourceAccessor") | .members[]?] | index($m) != null' >/dev/null 2>&1; then
  pass "Test identity holds roles/iap.httpsResourceAccessor"
else
  fail "Test identity holds roles/iap.httpsResourceAccessor" "${TEST_IDENTITY}"
fi

IAP_SETTINGS="$(gc iap settings get --resource-type=cloud-run --service="$SERVICE" --region="$REGION" --format=json 2>/dev/null)"
[ -n "$IAP_SETTINGS" ] || IAP_SETTINGS='{}'
CLIENT_ID="$(printf '%s' "$IAP_SETTINGS" | jq -r '.accessSettings.oauthSettings.programmaticClients[0] // ""' 2>/dev/null)"
if [ -n "$CLIENT_ID" ]; then
  pass "Programmatic client registered in the service's IAP settings"
else
  fail "Programmatic client registered in the service's IAP settings" "none found"
fi

if [ "$ENVIRONMENT" = "dev" ]; then
  APP_URL="$(jqs '.status.url // ""')"
  HEALTH_PATH="$(jqs '.spec.template.spec.containers[0].startupProbe.httpGet.path // "/health"')"
  if ! command -v curl >/dev/null 2>&1; then
    fail "End-to-end authentication checks" "curl not available"
  elif [ -z "$APP_URL" ]; then
    fail "End-to-end authentication checks" "service URL unknown"
  else
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${APP_URL}${HEALTH_PATH}" 2>/dev/null)"
    case "$code" in
      2* | 000 | '') fail "Anonymous request is rejected" "HTTP ${code:-none}" ;;
      *) pass "Anonymous request is rejected (HTTP ${code})" ;;
    esac
    TOKEN=""
    if [ -n "$CLIENT_ID" ]; then
      TOKEN="$(gcloud auth print-identity-token --impersonate-service-account="$TEST_IDENTITY" \
        --audiences="$CLIENT_ID" --include-email --quiet 2>/dev/null)"
    fi
    if [ -z "$TOKEN" ]; then
      fail "Authenticated request on ${HEALTH_PATH} returns 200" "could not obtain ID token for ${TEST_IDENTITY}"
      fail "Authenticated request on / returns 200" "could not obtain ID token for ${TEST_IDENTITY}"
    else
      for p in "$HEALTH_PATH" "/"; do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
          -H "Authorization: Bearer $TOKEN" "${APP_URL}${p}" 2>/dev/null)"
        eq "Authenticated request on ${p} returns 200" "$code" "200"
      done
    fi
  fi
fi

# ── Exposure ─────────────────────────────────────────────────────────────────
eq "Ingress is ${EXPECT_INGRESS}" "$(jqs '.metadata.annotations["run.googleapis.com/ingress"] // ""')" "$EXPECT_INGRESS"

if [ -n "$MAIN_DOMAIN" ]; then
  FR="$(gc compute forwarding-rules describe "fr-https-${PREFIX}" --region="$REGION" --format=json 2>/dev/null)"
  if [ -z "$FR" ]; then
    fail "HTTPS forwarding rule fr-https-${PREFIX} present" "not found"
  else
    eq "HTTPS forwarding rule scheme is ${EXPECT_LB_SCHEME}" \
      "$(printf '%s' "$FR" | jq -r '.loadBalancingScheme // ""')" "$EXPECT_LB_SCHEME"
  fi

  CERT_STATE="$(gc certificate-manager certificates describe "cert-${PREFIX}" --location="$REGION" --format=json 2>/dev/null |
    jq -r '.managed.state // ""' 2>/dev/null)"
  eq "Certificate cert-${PREFIX} is ACTIVE" "$CERT_STATE" "ACTIVE"

  AUTH_NAME="$(gc certificate-manager dns-authorizations describe "dnsauth-${PREFIX}" --location="$REGION" --format=json 2>/dev/null |
    jq -r '.dnsResourceRecord.name // ""' 2>/dev/null)"

  PUBLIC_ZONE="$(gc dns managed-zones list --format=json 2>/dev/null | jq -r --arg d "${MAIN_DOMAIN}." \
    '[.[] | select(.dnsName == $d and .visibility == "public") | .name] | first // ""' 2>/dev/null)"
  if [ -z "$PUBLIC_ZONE" ]; then
    fail "Public DNS zone for ${MAIN_DOMAIN} found" "no public zone"
  else
    PUB_RECORDS="$(gc dns record-sets list --zone="$PUBLIC_ZONE" --format=json 2>/dev/null)"
    [ -n "$PUB_RECORDS" ] || PUB_RECORDS='[]'
    if [ -n "$AUTH_NAME" ]; then
      if printf '%s' "$PUB_RECORDS" | jq -e --arg n "${AUTH_NAME%.}" \
        '[.[] | select(.type == "CNAME" and (.name | rtrimstr(".")) == $n)] | length > 0' >/dev/null 2>&1; then
        pass "DNS authorization CNAME present in the public zone"
      else
        fail "DNS authorization CNAME present in the public zone" "${AUTH_NAME}"
      fi
    else
      fail "DNS authorization CNAME present in the public zone" "dns authorization not found"
    fi
    PUB_APP="$(printf '%s' "$PUB_RECORDS" | jq -r --arg n "${APP_FQDN}." \
      '[.[] | select(.name == $n and (.type == "A" or .type == "AAAA" or .type == "CNAME"))] | length' 2>/dev/null)"
    if [ "$ENVIRONMENT" = "dev" ]; then
      if [ "${PUB_APP:-0}" -gt 0 ]; then
        pass "${APP_FQDN} present in the public zone"
      else
        fail "${APP_FQDN} present in the public zone" "not found"
      fi
    else
      if [ "${PUB_APP:-0}" -eq 0 ]; then
        pass "${APP_FQDN} absent from the public zone"
      else
        fail "${APP_FQDN} absent from the public zone" "record found"
      fi
    fi
  fi

  if [ "$ENVIRONMENT" != "dev" ]; then
    PRIV_RECORDS="$(gc dns record-sets list --zone="zone-app-${PREFIX}" --format=json 2>/dev/null)"
    [ -n "$PRIV_RECORDS" ] || PRIV_RECORDS='[]'
    if printf '%s' "$PRIV_RECORDS" | jq -e --arg n "${APP_FQDN}." \
      '[.[] | select(.name == $n and .type == "A")] | length > 0' >/dev/null 2>&1; then
      pass "${APP_FQDN} present in the private zone"
    else
      fail "${APP_FQDN} present in the private zone" "zone-app-${PREFIX}"
    fi
  fi
else
  echo "MAIN_DOMAIN not set: skipping certificate and DNS checks"
fi

# ── Autoscaling, resources, egress ───────────────────────────────────────────
eq "Min instances is ${EXPECT_MIN}" "$(jqs '.spec.template.metadata.annotations["autoscaling.knative.dev/minScale"] // ""')" "$EXPECT_MIN"
eq "Max instances is ${EXPECT_MAX}" "$(jqs '.spec.template.metadata.annotations["autoscaling.knative.dev/maxScale"] // ""')" "$EXPECT_MAX"
eq "CPU limit is ${EXPECT_CPU}" "$(jqs '.spec.template.spec.containers[0].resources.limits.cpu // ""')" "$EXPECT_CPU"
eq "Memory limit is ${EXPECT_MEMORY}" "$(jqs '.spec.template.spec.containers[0].resources.limits.memory // ""')" "$EXPECT_MEMORY"
eq "Egress routes all traffic through the VPC" \
  "$(jqs '.spec.template.metadata.annotations["run.googleapis.com/vpc-access-egress"] // ""')" "all-traffic"
CONN_ACTUAL="$(jqs '.spec.template.metadata.annotations["run.googleapis.com/vpc-access-connector"] // ""')"
eq "Egress goes through connector ${CONNECTOR}" "${CONN_ACTUAL##*/}" "$CONNECTOR"

# ── Logging and alerting ─────────────────────────────────────────────────────
BUCKET="$(gc logging buckets list --location=global --format=json 2>/dev/null | jq -c --arg p "/buckets/run-${PREFIX}-" \
  '[.[] | select(.name | contains($p))] | first // empty' 2>/dev/null)"
if [ -z "$BUCKET" ]; then
  fail "Cloud Logging bucket run-${PREFIX}-* exists" "not found"
else
  pass "Cloud Logging bucket run-${PREFIX}-* exists"
  eq "Log bucket retention is ${LOG_RETENTION_DAYS} days" "$(printf '%s' "$BUCKET" | jq -r '.retentionDays // ""')" "$LOG_RETENTION_DAYS"
fi
check "Log sink sink-run-${PREFIX} exists" "not found" \
  gc logging sinks describe "sink-run-${PREFIX}"

POLICIES="$(gc monitoring policies list --format=json 2>/dev/null)"
[ -n "$POLICIES" ] || POLICIES='[]'
for suffix in run-cpu-high run-memory-high run-instance-count-low; do
  if printf '%s' "$POLICIES" | jq -e --arg n "${PREFIX}-${suffix}" '[.[] | select(.displayName == $n)] | length > 0' >/dev/null 2>&1; then
    pass "Alert policy ${PREFIX}-${suffix} exists"
  else
    fail "Alert policy ${PREFIX}-${suffix} exists" "not found"
  fi
done

# ── Networking posture ───────────────────────────────────────────────────────
check "VPC vpc-${PREFIX} exists" "not found" gc compute networks describe "vpc-${PREFIX}"
for name in "snet-app-${PREFIX}" "snet-services-${PREFIX}" "snet-vpcc-${PREFIX}"; do
  eq "Subnet ${name} has flow logs enabled" \
    "$(gc compute networks subnets describe "$name" --region="$REGION" --format=json 2>/dev/null | jq -r '.logConfig.enable // false' 2>/dev/null)" "true"
done
check "Cloud NAT nat-${PREFIX} exists" "not found" \
  gc compute routers nats describe "nat-${PREFIX}" --router="cr-${PREFIX}" --region="$REGION"
eq "VPC connector ${CONNECTOR} is READY" \
  "$(gc compute networks vpc-access connectors describe "$CONNECTOR" --region="$REGION" --format=json 2>/dev/null | jq -r '.state // ""' 2>/dev/null)" "READY"

# ── Service account posture ──────────────────────────────────────────────────
RUNTIME_SA="$(jqs '.spec.template.spec.serviceAccountName // ""')"
PROJECT_IAM="$(gc projects get-iam-policy "$PROJECT" --format=json 2>/dev/null)"
[ -n "$PROJECT_IAM" ] || PROJECT_IAM='{}'
sa_roles() {
  printf '%s' "$PROJECT_IAM" | jq -r --arg m "serviceAccount:$1" \
    '[.bindings[]? | select(.members | index($m)) | .role] | sort | .[]' 2>/dev/null
}
if [ -z "$RUNTIME_SA" ]; then
  fail "Runtime service account holds only the expected roles" "runtime service account unknown"
else
  ROLES="$(sa_roles "$RUNTIME_SA")"
  missing=""
  for r in roles/logging.logWriter roles/monitoring.metricWriter; do
    printf '%s\n' "$ROLES" | grep -qx "$r" || missing="${missing} ${r}"
  done
  extra="$(printf '%s\n' "$ROLES" | grep -v -x -e '' -e roles/logging.logWriter -e roles/monitoring.metricWriter -e roles/cloudtrace.agent | tr '\n' ' ')"
  if [ -z "$missing" ] && [ -z "$extra" ]; then
    pass "Runtime service account holds only the expected roles"
  else
    fail "Runtime service account holds only the expected roles" "missing:${missing:- none}; unexpected: ${extra:-none}"
  fi
fi
TEST_ROLES="$(sa_roles "$TEST_IDENTITY" | tr '\n' ' ')"
if [ -z "$TEST_ROLES" ]; then
  pass "Test identity holds no project-level roles"
else
  fail "Test identity holds no project-level roles" "$TEST_ROLES"
fi

# ── Result ───────────────────────────────────────────────────────────────────
echo
echo "environment=${ENVIRONMENT} passed=${PASSED} failed=${FAILED}"
write_summary
if [ "$FAILED" -gt 0 ]; then exit 1; fi
exit 0
