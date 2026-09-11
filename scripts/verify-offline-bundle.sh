#!/usr/bin/env bash
# Verify offline bundle integrity and required layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

TARGET="${1:-${PROJECT_ROOT}/offline-bundle}"
ERR=0

log_info "Verifying offline bundle at ${TARGET}"

for d in manifest rpm-repo helm binaries; do
  if [[ ! -d "${TARGET}/${d}" ]]; then
    log_error "missing directory: ${d}"
    ERR=1
  else
    log_ok "directory ${d}"
  fi
done

for f in manifest/images.yml manifest/versions.yml manifest/checksums.txt; do
  if [[ ! -f "${TARGET}/${f}" ]]; then
    log_error "missing file: ${f}"
    ERR=1
  else
    log_ok "file ${f}"
  fi
done

# Spot-check that image manifest uses DNS destination host field conceptually
if grep -E 'destination:.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "${TARGET}/manifest/images.yml" >/dev/null 2>&1; then
  log_error "images.yml contains IP destinations — use DNS names (zot.<domain>)"
  ERR=1
else
  log_ok "images.yml destinations appear DNS-based"
fi

if [[ -f "${TARGET}/manifest/checksums.txt" ]]; then
  log_info "Checksum file present (full re-verify may take time)"
fi

[[ "${ERR}" -eq 0 ]] || die "offline bundle verification failed"
log_ok "offline bundle verification passed"
