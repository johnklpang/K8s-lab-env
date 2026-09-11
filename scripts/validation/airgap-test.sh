#!/usr/bin/env bash
# Air-gap validation — must not require Internet; verify local DNS repos/registry.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

export OFFLINE_MODE=1
resolve_config "${PROFILE:-minimal}"
REPORT="${PROJECT_ROOT}/reports/airgap-$(timestamp).txt"
ERR=0

{
  echo "Air-gap Validation Report"
  echo "domain=$(lab_domain)"
  echo "zot=$(url_of zot)"
  echo "repo=$(url_of repo)"
  echo "helm=$(url_of helm)"
} | tee "${REPORT}"

log_info "Verifying no reliance on external Internet for core endpoints"

for name in zot repo helm; do
  url="$(url_of "${name}")"
  if curl -fsS --connect-timeout 3 "${url}" >/dev/null 2>&1 || curl -fsS --connect-timeout 3 "${url}/" >/dev/null 2>&1; then
    log_ok "local endpoint reachable via DNS: ${url}"
    echo "PASS ${name} ${url}" >>"${REPORT}"
  else
    log_error "local endpoint FAILED: ${url}"
    echo "FAIL ${name} ${url}" >>"${REPORT}"
    ERR=1
  fi
done

# Detect unexpected external resolution dependency
if getent hosts registry.k8s.io >/dev/null 2>&1; then
  log_warn "registry.k8s.io resolves — ensure pulls are rewritten to $(fqdn_of zot)"
  echo "WARN external_name_resolves registry.k8s.io" >>"${REPORT}"
fi

if command -v kubectl >/dev/null 2>&1; then
  kubectl get nodes >>"${REPORT}" 2>&1 || ERR=1
fi

[[ "${ERR}" -eq 0 ]] || die "air-gap validation failed — see ${REPORT}"
log_ok "air-gap validation passed — ${REPORT}"
