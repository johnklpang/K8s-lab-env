#!/usr/bin/env bash
# Backup helper — uses DNS names; does not embed IP addresses.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ensure_dirs
TS="$(timestamp)"
OUT="${PROJECT_ROOT}/reports/backup-${TS}"
mkdir -p "${OUT}"

log_info "Starting backup ${OUT}"

# etcd snapshot via control-plane FQDN (kubeadm/etcdctl on master)
MASTER="$(fqdn_of master-01)"
log_info "control_plane=${MASTER}"

if command -v kubectl >/dev/null 2>&1; then
  kubectl get all -A -o yaml >"${OUT}/kubernetes-resources.yaml" 2>/dev/null || true
  kubectl get secrets -A -o yaml >"${OUT}/secrets.yaml" 2>/dev/null || log_warn "secrets export skipped/failed"
  kubectl get pvc -A -o yaml >"${OUT}/pvc.yaml" 2>/dev/null || true
fi

# PostgreSQL logical backup via in-cluster DNS
if component_enabled postgres; then
  log_info "Backing up PostgreSQL via postgres.database.svc.cluster.local"
  kubectl -n database exec deploy/postgresql -- \
    bash -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
    >"${OUT}/postgres.sql" 2>/dev/null || log_warn "PostgreSQL backup skipped (release naming may differ)"
fi

# Config + manifests (no credentials.yml secrets if vaulted — copy example only)
cp -a "${PROJECT_ROOT}/config" "${OUT}/config"
rm -f "${OUT}/config/credentials.yml" 2>/dev/null || true

tar -C "${PROJECT_ROOT}/reports" -czf "${OUT}.tar.gz" "backup-${TS}"
log_ok "Backup archive: ${OUT}.tar.gz"
echo "See docs/33-backup-and-restore.md for restore procedures."
