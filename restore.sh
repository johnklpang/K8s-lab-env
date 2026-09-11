#!/usr/bin/env bash
# Restore helper — requires explicit backup archive path.
# Destructive operations require confirmation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ARCHIVE="${1:-}"
CONFIRM="${CONFIRM_RESTORE:-}"

usage() {
  echo "Usage: CONFIRM_RESTORE=yes ./restore.sh /path/to/backup-YYYY-MM-DD-HHMMSS.tar.gz"
}

[[ -n "${ARCHIVE}" ]] || { usage; die "backup archive required"; }
[[ -f "${ARCHIVE}" ]] || die "archive not found: ${ARCHIVE}"
[[ "${CONFIRM}" == "yes" ]] || die "Refusing restore without CONFIRM_RESTORE=yes"

ensure_dirs
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
tar -xzf "${ARCHIVE}" -C "${TMP}"
SRC="$(find "${TMP}" -maxdepth 1 -type d -name 'backup-*' | head -1)"
[[ -n "${SRC}" ]] || die "invalid backup archive layout"

log_warn "Restoring from ${ARCHIVE}"
log_info "PostgreSQL restore uses DNS name postgres.database.svc.cluster.local"

if [[ -f "${SRC}/postgres.sql" ]] && component_enabled postgres; then
  kubectl -n database exec -i deploy/postgresql -- \
    bash -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" "$POSTGRES_DB"' \
    <"${SRC}/postgres.sql" || log_warn "PostgreSQL restore encountered errors"
fi

log_ok "Restore steps completed for available artifacts"
log_info "etcd restore is documented in docs/33-backup-and-restore.md (manual on control-plane FQDN)"
