#!/usr/bin/env bash
# Health-check Zot via DNS name.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
URL="$(url_of zot)"
curl -fsS "${URL}/v2/" >/dev/null
log_ok "Zot healthy at ${URL}"
