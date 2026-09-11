#!/usr/bin/env bash
# Import offline bundle on an air-gapped OPS node.
# Configures DNS names for zot/repo/helm — never requires Internet.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ARCHIVE="${1:-}"
[[ -n "${ARCHIVE}" ]] || die "Usage: ./scripts/import-offline-bundle.sh /path/to/k8s-offline-bundle-<version>.tar.zst"

ensure_dirs
log_info "Importing ${ARCHIVE}"
export OFFLINE_MODE=1

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

case "${ARCHIVE}" in
  *.tar.zst)
    require_cmd tar
    if command -v zstd >/dev/null 2>&1; then
      tar -I zstd -xf "${ARCHIVE}" -C "${TMP}"
    else
      die "zstd required to extract ${ARCHIVE}"
    fi
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "${ARCHIVE}" -C "${TMP}"
    ;;
  *)
    die "Unsupported archive format: ${ARCHIVE}"
    ;;
esac

SRC="$(find "${TMP}" -maxdepth 2 -type d -name offline-bundle | head -1)"
[[ -n "${SRC}" ]] || die "offline-bundle directory not found in archive"

bash "${PROJECT_ROOT}/scripts/verify-offline-bundle.sh" "${SRC}"

rsync -a "${SRC}/" "${PROJECT_ROOT}/offline-bundle/" 2>/dev/null || cp -a "${SRC}/." "${PROJECT_ROOT}/offline-bundle/"

# Generate inventory + DNS from central config
resolve_config "${PROFILE:-minimal}"

ZOT="$(fqdn_of zot)"
REPO="$(fqdn_of repo)"
HELM="$(fqdn_of helm)"
OPS="$(fqdn_of ops)"

log_info "Configuring local endpoints:"
log_info "  DNS/OPS: ${OPS}"
log_info "  Zot:     $(url_of zot)"
log_info "  RPM:     $(url_of repo)"
log_info "  Helm:    $(url_of helm)"

# Install generated dnsmasq config if root
if [[ "$(id -u)" -eq 0 ]] || sudo -n true 2>/dev/null; then
  SUDO="sudo"
  [[ "$(id -u)" -eq 0 ]] && SUDO=""
  ${SUDO} mkdir -p /etc/dnsmasq.d
  ${SUDO} cp "${PROJECT_ROOT}/scripts/dns/generated/dnsmasq.conf" /etc/dnsmasq.d/lab.conf
  ${SUDO} systemctl enable --now dnsmasq 2>/dev/null || log_warn "dnsmasq service not installed yet — Ansible dns role will complete this"
else
  log_warn "No root/sudo — skip live dnsmasq install; Ansible will configure DNS"
fi

# Import report
REPORT="${PROJECT_ROOT}/reports/import-$(timestamp).txt"
{
  echo "Offline Import Report"
  echo "Archive: ${ARCHIVE}"
  echo "Zot DNS: ${ZOT}"
  echo "Repo DNS: ${REPO}"
  echo "Helm DNS: ${HELM}"
  echo "Mode: offline (Internet not required)"
  echo "Status: imported layout + generated DNS/inventory"
} | tee "${REPORT}"

log_ok "Import complete — next: ./deploy.sh --profile minimal"
log_info "report=${REPORT}"
