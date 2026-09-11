#!/usr/bin/env bash
# Update workflow wrapper for Internet-connected OPS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
log_info "Updating offline bundle artifacts"
bash "${ROOT}/scripts/prepare/prepare-offline.sh" "${PROFILE:-minimal}"
bash "${ROOT}/scripts/package-offline-bundle.sh"
log_ok "Update bundle created — transfer securely to offline OPS"
