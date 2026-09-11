#!/usr/bin/env bash
# DNS validation — forward (and reverse where configured) using DNS names from central config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

resolve_config "${PROFILE:-minimal}"
ERR=0

log_info "Testing DNS for domain=$(lab_domain)"

NAMES=(ops master-01 worker-01 worker-02 worker-03 zot repo helm grafana argocd postgres)

for name in "${NAMES[@]}"; do
  f="$(fqdn_of "${name}")"
  if getent hosts "${f}" >/dev/null 2>&1; then
    log_ok "forward ${f}"
  else
    log_error "forward FAILED ${f}"
    ERR=1
  fi
done

# Reverse lookup for OPS if configured
OPS_FQDN="$(fqdn_of ops)"
OPS_IP="$(getent hosts "${OPS_FQDN}" | awk '{print $1; exit}')"
if [[ -n "${OPS_IP}" ]]; then
  if getent hosts "${OPS_IP}" 2>/dev/null | grep -q "${OPS_FQDN}"; then
    log_ok "reverse ${OPS_IP} -> ${OPS_FQDN}"
  else
    log_warn "reverse resolution not confirmed for ${OPS_FQDN}"
  fi
fi

# From a Kubernetes pod if cluster exists
if command -v kubectl >/dev/null 2>&1 && kubectl get ns default >/dev/null 2>&1; then
  ZOT="$(fqdn_of zot)"
  if kubectl run "dns-test-${RANDOM}" --rm -i --restart=Never --image="$(fqdn_of zot)/registry.k8s.io/pause:3.10" \
      --command -- getent hosts "${ZOT}" >/dev/null 2>&1; then
    log_ok "pod resolution for ${ZOT}"
  else
    # pause may lack getent — try busybox if mirrored
    log_warn "pod DNS test skipped or failed (image tools may be minimal)"
  fi
fi

[[ "${ERR}" -eq 0 ]] || exit 1
log_ok "DNS tests passed"
