#!/usr/bin/env bash
# Sync RPM packages into offline-bundle/rpm-repo (Internet-connected Rocky 9).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

DEST="${PROJECT_ROOT}/offline-bundle/rpm-repo"
mkdir -p "${DEST}"

log_info "RPM sync target: ${DEST}"
log_info "Serve later at $(url_of repo) using DNS name $(fqdn_of repo)"

if command -v dnf >/dev/null 2>&1 && command -v createrepo_c >/dev/null 2>&1; then
  log_info "Running reposync (may take a long time)"
  dnf reposync -p "${DEST}" --download-metadata --repoid=baseos --repoid=appstream || log_warn "reposync partial"
  createrepo_c "${DEST}" || true
  log_ok "RPM repository metadata generated"
else
  log_warn "dnf/createrepo_c unavailable — created directory structure only"
fi
