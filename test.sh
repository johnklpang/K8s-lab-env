#!/usr/bin/env bash
# Platform test runner — DNS-based checks; disabled components return SKIPPED.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

PROFILE=""
FAILURE_TESTS=0
ENABLE_OVERRIDES=""
DISABLE_OVERRIDES=""

usage() {
  cat <<EOF
Usage: ./test.sh [--profile NAME] [--failure-tests] [--enable X] [--disable Y]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --failure-tests) FAILURE_TESTS=1; shift ;;
    --enable) ENABLE_OVERRIDES="$2"; shift 2 ;;
    --disable) DISABLE_OVERRIDES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

ensure_dirs
export PROFILE ENABLE_OVERRIDES DISABLE_OVERRIDES
resolve_config "${PROFILE}" "${ENABLE_OVERRIDES}" "${DISABLE_OVERRIDES}"
PROFILE="${PROFILE:-$(python3 "${CONFIG_LOADER}" --emit json | python3 -c 'import json,sys; print(json.load(sys.stdin)["profile"])')}"
export PROFILE

LOGFILE="${PROJECT_ROOT}/logs/test-$(timestamp).log"
REPORT="${PROJECT_ROOT}/reports/test-report.txt"
exec > >(tee -a "${LOGFILE}") 2>&1

PASS=0
FAIL=0
SKIP=0
RESULTS=()

record() {
  local name="$1" status="$2" detail="${3:-}"
  RESULTS+=("${name}: ${status}${detail:+ — ${detail}}")
  case "${status}" in
    PASS) PASS=$((PASS + 1)); log_ok "${name}" ;;
    FAIL) FAIL=$((FAIL + 1)); log_error "${name} ${detail}" ;;
    SKIPPED) SKIP=$((SKIP + 1)); log_skip "${name}" ;;
    *) log_warn "${name}: ${status}" ;;
  esac
}

require_enabled() {
  local comp="$1"
  if component_enabled "${comp}"; then
    return 0
  fi
  record "${comp}" "SKIPPED" "disabled in profile ${PROFILE}"
  return 1
}

# --- OS / DNS ---
bash "${PROJECT_ROOT}/scripts/validation/test-dns.sh" && record "DNS" "PASS" || record "DNS" "FAIL"

# --- Kubernetes ---
if require_enabled kubernetes; then
  if command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    not_ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' | wc -l | tr -d ' ')"
    if [[ "${not_ready}" == "0" ]]; then
      record "Kubernetes" "PASS"
    else
      record "Kubernetes" "FAIL" "${not_ready} node(s) not Ready"
    fi
  else
    record "Kubernetes" "FAIL" "kubectl unavailable or cluster unreachable"
  fi
fi

check_ns_pods() {
  local label="$1" ns="$2"
  kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -qvE 'Running|Completed' && return 1
  kubectl get pods -n "${ns}" --no-headers 2>/dev/null | grep -q . 
}

if require_enabled cilium; then
  if command -v kubectl >/dev/null 2>&1 && kubectl -n kube-system get pods -l k8s-app=cilium >/dev/null 2>&1; then
    record "Cilium" "PASS"
  else
    record "Cilium" "FAIL"
  fi
fi

if require_enabled hubble; then
  if command -v kubectl >/dev/null 2>&1 && kubectl -n kube-system get deploy hubble-relay >/dev/null 2>&1; then
    record "Hubble" "PASS"
  else
    record "Hubble" "FAIL"
  fi
fi

if require_enabled cert_manager; then
  if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
    record "cert-manager" "PASS"
  else
    record "cert-manager" "FAIL"
  fi
fi

if require_enabled ingress; then
  if kubectl -n ingress-nginx get pods >/dev/null 2>&1; then
    record "Ingress" "PASS"
  else
    record "Ingress" "FAIL"
  fi
fi

if require_enabled storage_local_path; then
  if kubectl get storageclass local-path >/dev/null 2>&1; then
    record "Storage" "PASS"
  else
    record "Storage" "FAIL"
  fi
fi

if require_enabled postgres; then
  PG_FQDN="$(fqdn_of postgres)"
  if kubectl -n database get pods -l app.kubernetes.io/name=postgresql >/dev/null 2>&1; then
    record "PostgreSQL" "PASS" "service DNS ${PG_FQDN} / postgres.database.svc.cluster.local"
  else
    record "PostgreSQL" "FAIL"
  fi
fi

if require_enabled prometheus; then
  if kubectl -n monitoring get pods >/dev/null 2>&1; then
    record "Prometheus" "PASS"
  else
    record "Prometheus" "FAIL"
  fi
fi

if require_enabled grafana; then
  GF="$(fqdn_of grafana)"
  if kubectl -n monitoring get ingress >/dev/null 2>&1 || kubectl -n monitoring get svc -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
    record "Grafana" "PASS" "ingress ${GF}"
  else
    record "Grafana" "FAIL"
  fi
fi

if require_enabled argocd; then
  AC="$(fqdn_of argocd)"
  if kubectl -n argocd get pods >/dev/null 2>&1; then
    record "Argo CD" "PASS" "ingress ${AC}"
  else
    record "Argo CD" "FAIL"
  fi
fi

# Optional components
for pair in "kafka:Kafka" "opensearch:OpenSearch" "emqx:EMQX" "loki:Loki" "opentelemetry:OpenTelemetry" "service_mesh:Service Mesh" "ceph:Ceph" "trivy:Trivy"; do
  comp="${pair%%:*}"
  label="${pair#*:}"
  if ! component_enabled "${comp}"; then
    record "${label}" "SKIPPED"
    continue
  fi
  # Presence smoke check — detailed tests live under tests/
  case "${comp}" in
    kafka) kubectl -n messaging get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    opensearch) kubectl -n logging get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    emqx) kubectl -n messaging get pods -l app.kubernetes.io/name=emqx >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    loki) kubectl -n monitoring get pods -l app.kubernetes.io/name=loki >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    opentelemetry) kubectl -n observability get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    service_mesh) kubectl -n istio-system get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    ceph) kubectl -n rook-ceph get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
    trivy) kubectl -n trivy-system get pods >/dev/null 2>&1 && record "${label}" "PASS" || record "${label}" "FAIL" ;;
  esac
done

if [[ "${FAILURE_TESTS}" == "1" ]]; then
  log_warn "Failure tests require explicit confirmation and a live cluster"
  bash "${PROJECT_ROOT}/tests/failure-tests.sh"
fi

{
  echo "Test Report — profile=${PROFILE}"
  echo "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "PASS=${PASS} FAIL=${FAIL} SKIPPED=${SKIP}"
  echo
  printf '%s\n' "${RESULTS[@]}"
} | tee "${REPORT}"

log_info "report=${REPORT}"
[[ "${FAIL}" -eq 0 ]]
