#!/usr/bin/env bash
# Collect diagnostics without embedding secrets by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ensure_dirs
TS="$(timestamp)"
OUTDIR="${PROJECT_ROOT}/reports/diagnostic-${TS}"
ARCHIVE="${PROJECT_ROOT}/reports/diagnostic-${TS}.tar.gz"
mkdir -p "${OUTDIR}"

log_info "Collecting diagnostics into ${OUTDIR}"

{
  echo "hostname=$(hostname -f 2>/dev/null || hostname)"
  echo "date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  uname -a
  cat /etc/os-release 2>/dev/null || true
  lscpu 2>/dev/null | head -40 || true
  free -h || true
  df -h || true
} >"${OUTDIR}/os.txt"

{
  echo "=== DNS ==="
  lab_domain || true
  fqdn_of ops || true
  fqdn_of zot || true
  getent hosts "$(fqdn_of ops 2>/dev/null || echo ops)" || true
  getent hosts "$(fqdn_of zot 2>/dev/null || echo zot)" || true
  resolvectl status 2>/dev/null || cat /etc/resolv.conf || true
} >"${OUTDIR}/dns.txt"

systemctl is-active containerd >"${OUTDIR}/containerd.txt" 2>&1 || true
systemctl status containerd --no-pager >"${OUTDIR}/containerd-status.txt" 2>&1 || true

if command -v kubectl >/dev/null 2>&1; then
  kubectl get nodes -o wide >"${OUTDIR}/nodes.txt" 2>&1 || true
  kubectl get pods -A -o wide >"${OUTDIR}/pods.txt" 2>&1 || true
  kubectl get svc -A >"${OUTDIR}/services.txt" 2>&1 || true
  kubectl get ingress -A >"${OUTDIR}/ingress.txt" 2>&1 || true
  kubectl get events -A --sort-by=.lastTimestamp | tail -200 >"${OUTDIR}/events.txt" 2>&1 || true
  kubectl -n kube-system get pods >"${OUTDIR}/kube-system-pods.txt" 2>&1 || true
  command -v cilium >/dev/null 2>&1 && cilium status >"${OUTDIR}/cilium.txt" 2>&1 || true
fi

if command -v helm >/dev/null 2>&1; then
  helm list -A >"${OUTDIR}/helm.txt" 2>&1 || true
fi

# Registry / repo via DNS names
{
  echo "zot=$(url_of zot 2>/dev/null || true)"
  curl -fsS "$(url_of zot 2>/dev/null)/v2/" >/dev/null 2>&1 && echo "zot_health=OK" || echo "zot_health=FAIL"
  echo "repo=$(url_of repo 2>/dev/null || true)"
  curl -fsS "$(url_of repo 2>/dev/null)" >/dev/null 2>&1 && echo "repo_health=OK" || echo "repo_health=FAIL"
  echo "helm=$(url_of helm 2>/dev/null || true)"
  curl -fsS "$(url_of helm 2>/dev/null)" >/dev/null 2>&1 && echo "helm_health=OK" || echo "helm_health=FAIL"
} >"${OUTDIR}/endpoints.txt"

tar -C "${PROJECT_ROOT}/reports" -czf "${ARCHIVE}" "diagnostic-${TS}"
log_ok "Wrote ${ARCHIVE}"
echo "${ARCHIVE}"
