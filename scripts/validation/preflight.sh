#!/usr/bin/env bash
# Preflight checks — prefer warnings for LAB resource limits.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

PROFILE="minimal"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export PROFILE
resolve_config "${PROFILE}"
ERR=0
WARN=0

log_info "Preflight for profile=${PROFILE}"

# Hostname / FQDN
HN="$(hostname -f 2>/dev/null || hostname)"
log_info "hostname=${HN}"
if [[ "${HN}" != *.* ]]; then
  log_warn "FQDN not fully qualified: ${HN}"
  WARN=$((WARN + 1))
fi

# OS
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "rocky" && "${VERSION_ID:-}" == 9* ]]; then
    log_ok "Rocky Linux 9"
  else
    log_warn "Expected Rocky Linux 9, found ${ID:-unknown} ${VERSION_ID:-}"
    WARN=$((WARN + 1))
  fi
fi

# Resources
CPUS="$(nproc 2>/dev/null || echo 0)"
MEM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
if [[ "${CPUS}" -lt 2 ]]; then
  log_warn "CPU < 2 (LAB minimum)"
  WARN=$((WARN + 1))
else
  log_ok "CPU=${CPUS}"
fi
if [[ "${MEM_MB}" -lt 1800 ]]; then
  log_warn "Memory ${MEM_MB}MB < LAB target ~2GB — resource pressure likely"
  WARN=$((WARN + 1))
else
  log_ok "Memory=${MEM_MB}MB"
fi

# DNS endpoints
for name in ops zot repo helm; do
  f="$(fqdn_of "${name}")"
  if getent hosts "${f}" >/dev/null 2>&1; then
    log_ok "DNS resolves ${f}"
  else
    log_warn "DNS not yet resolving ${f} (expected before dns stage completes)"
    WARN=$((WARN + 1))
  fi
done

# Tools on OPS
for cmd in python3 ansible-playbook helm kubectl; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    log_ok "tool ${cmd}"
  else
    log_warn "tool missing: ${cmd}"
    WARN=$((WARN + 1))
  fi
done

python3 "${CONFIG_LOADER}" --profile "${PROFILE}" --emit validate-deps || ERR=1

log_info "preflight warnings=${WARN} errors=${ERR}"
[[ "${ERR}" -eq 0 ]] || die "preflight failed"
log_ok "preflight complete"
