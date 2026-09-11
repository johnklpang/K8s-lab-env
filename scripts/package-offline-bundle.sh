#!/usr/bin/env bash
# Package offline-bundle into a version-pinned tar.zst archive.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ensure_dirs
BUNDLE="${PROJECT_ROOT}/offline-bundle"
[[ -d "${BUNDLE}/manifest" ]] || die "Run prepare-offline.sh first"

VERSION="$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config/versions.yml'))['bundle_version'])")"
OUT="${PROJECT_ROOT}/k8s-offline-bundle-${VERSION}.tar.zst"

log_info "Packaging ${BUNDLE} -> ${OUT}"
require_cmd tar
if command -v zstd >/dev/null 2>&1; then
  tar -C "${PROJECT_ROOT}" -I 'zstd -T0 -19' -cf "${OUT}" offline-bundle
else
  log_warn "zstd not found — creating .tar.gz instead"
  OUT="${PROJECT_ROOT}/k8s-offline-bundle-${VERSION}.tar.gz"
  tar -C "${PROJECT_ROOT}" -czf "${OUT}" offline-bundle
fi

(
  cd "${PROJECT_ROOT}"
  sha256sum "$(basename "${OUT}")" >"$(basename "${OUT}").sha256"
)
log_ok "Created ${OUT}"
echo "${OUT}"
