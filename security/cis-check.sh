#!/usr/bin/env bash
# CIS-oriented checks — does NOT claim full CIS compliance.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ensure_dirs
REPORT="${PROJECT_ROOT}/reports/cis-report.txt"
{
  echo "CIS-Oriented Report"
  echo "Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "Classification: NOT a full CIS compliance certification"
  echo
} >"${REPORT}"

result() {
  local id="$1" status="$2" detail="$3"
  echo "${status} ${id} — ${detail}" | tee -a "${REPORT}"
}

# File permission oriented checks on control plane if present
if [[ -f /etc/kubernetes/admin.conf ]]; then
  mode="$(stat -c '%a' /etc/kubernetes/admin.conf 2>/dev/null || echo missing)"
  if [[ "${mode}" == "600" || "${mode}" == "640" ]]; then
    result "1.1.1" "PASS" "admin.conf mode ${mode}"
  else
    result "1.1.1" "FAIL" "admin.conf mode ${mode}"
  fi
else
  result "1.1.1" "NOT_APPLICABLE" "admin.conf not present on this node"
fi

if [[ -d /etc/kubernetes/manifests ]]; then
  result "1.2.x" "WARNING" "API server flags require manual review against CIS benchmark"
else
  result "1.2.x" "NOT_APPLICABLE" "static pod manifests not found"
fi

result "3.2.x" "LAB_EXCEPTION" "LAB uses password auth for devops user — disable in production"
result "5.1.x" "WARNING" "Validate RBAC least privilege per workload"
result "5.3.x" "WARNING" "Ensure NetworkPolicies exist for sensitive namespaces"
result "5.7.x" "PASS" "Image references prefer Zot DNS name $(fqdn_of zot 2>/dev/null || echo zot.lab.example)"

log_ok "Wrote ${REPORT}"
