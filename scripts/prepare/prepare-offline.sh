#!/usr/bin/env bash
# Internet-connected preparation: download and stage all offline artifacts.
# Uses DNS names for local registry endpoints (zot.<domain>).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

PROFILE="${1:-${PROFILE:-minimal}}"
ENABLE_OVERRIDES="${ENABLE_OVERRIDES:-}"
DISABLE_OVERRIDES="${DISABLE_OVERRIDES:-}"
export PROFILE

ensure_dirs
resolve_config "${PROFILE}" "${ENABLE_OVERRIDES}" "${DISABLE_OVERRIDES}"

BUNDLE="${PROJECT_ROOT}/offline-bundle"
mkdir -p "${BUNDLE}"/{manifest,rpm-repo,container-images,helm,binaries,ansible,git,configs,scripts,certificates,documentation,tests,checksums}

LOGFILE="${PROJECT_ROOT}/logs/prepare-$(timestamp).log"
exec > >(tee -a "${LOGFILE}") 2>&1

log_info "Preparing offline bundle for profile=${PROFILE}"
log_info "Classification: Internet preparation — artifacts are version-pinned"

require_cmd python3 curl tar gzip sha256sum
command -v podman >/dev/null 2>&1 || command -v skopeo >/dev/null 2>&1 || log_warn "podman/skopeo recommended for image mirroring"

# 1) Internet connectivity
if [[ "$(detect_offline_mode)" == "offline" ]]; then
  die "Internet connectivity required for prepare-offline.sh"
fi
log_ok "Internet connectivity detected"

# 2) OS check (warn if not Rocky 9 — preparation may still run on compatible hosts)
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "rocky" || "${VERSION_ID:-}" != 9* ]]; then
    log_warn "Preparation host is ${ID:-unknown} ${VERSION_ID:-unknown}; target platform is Rocky Linux 9"
  else
    log_ok "Rocky Linux 9 detected"
  fi
fi

ZOT_FQDN="$(fqdn_of zot)"
ZOT_URL="$(url_of zot)"
log_info "Local registry endpoint (DNS): ${ZOT_URL} (${ZOT_FQDN})"

# Copy pinned versions into bundle manifest
cp "${PROJECT_ROOT}/config/versions.yml" "${BUNDLE}/manifest/versions.yml"
cp "${PROJECT_ROOT}/config/versions.yml" "${BUNDLE}/manifest/software-manifest.yml"

# Discover images from charts/manifests and component list
python3 "${PROJECT_ROOT}/scripts/images/discover-images.py" --profile "${PROFILE}" \
  --out-yml "${BUNDLE}/manifest/images.yml" \
  --out-txt "${BUNDLE}/manifest/images.txt"
log_ok "image manifest generated"

# Stage Helm charts metadata (download when helm available)
mkdir -p "${BUNDLE}/helm"
python3 "${PROJECT_ROOT}/scripts/helm/prepare-charts.py" --profile "${PROFILE}" --out "${BUNDLE}/helm"
log_ok "Helm chart staging complete"

# Stage binaries list (actual download best-effort)
BIN_DIR="${BUNDLE}/binaries"
mkdir -p "${BIN_DIR}"
K8S_VER="$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config/versions.yml'))['kubernetes']['version'])")"
HELM_VER="$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config/versions.yml'))['helm']['version'])")"
cat >"${BIN_DIR}/README.md" <<EOF
# Offline binaries

Pinned versions:
- kubectl/kubeadm/kubelet: ${K8S_VER}
- helm: ${HELM_VER}

Download during Internet preparation using official sources listed in docs/35-references.md.
Registry and cluster endpoints use DNS names such as ${ZOT_FQDN}.
EOF

# Best-effort binary downloads
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) GOARCH=amd64 ;;
  aarch64) GOARCH=arm64 ;;
  *) GOARCH=amd64 ;;
esac

download() {
  local url="$1" dest="$2"
  log_info "Download ${url}"
  if curl -fsSL "${url}" -o "${dest}"; then
    log_ok "saved ${dest}"
  else
    log_warn "failed to download ${url} — record for manual fetch"
    echo "${url}" >>"${BUNDLE}/manifest/missing-downloads.txt"
  fi
}

download "https://get.helm.sh/helm-v${HELM_VER}-linux-${GOARCH}.tar.gz" "${BIN_DIR}/helm-v${HELM_VER}-linux-${GOARCH}.tar.gz" || true
download "https://dl.k8s.io/release/v${K8S_VER}/bin/linux/${GOARCH}/kubectl" "${BIN_DIR}/kubectl" || true

# RPM repository placeholder structure + sync helper
mkdir -p "${BUNDLE}/rpm-repo/rocky/9/BaseOS" "${BUNDLE}/rpm-repo/kubernetes"
cat >"${BUNDLE}/rpm-repo/README.md" <<EOF
# Offline RPM repository

Serve via nginx at http://$(fqdn_of repo)/rpm/ (DNS name — no hardcoded IP).
Use scripts/prepare/sync-rpm-repo.sh on an Internet-connected Rocky 9 OPS node
to populate packages with reposync/createrepo_c.
EOF

# Copy configs and scripts into bundle
rsync -a --exclude '.git' --exclude 'offline-bundle' --exclude 'logs' --exclude 'reports' --exclude 'state' \
  "${PROJECT_ROOT}/config" "${BUNDLE}/configs/" 2>/dev/null || cp -a "${PROJECT_ROOT}/config" "${BUNDLE}/configs/"
cp -a "${PROJECT_ROOT}/docs" "${BUNDLE}/documentation/" 2>/dev/null || true
cp -a "${PROJECT_ROOT}/scripts" "${BUNDLE}/scripts/" 2>/dev/null || true
cp -a "${PROJECT_ROOT}/ansible" "${BUNDLE}/ansible/" 2>/dev/null || true
cp -a "${PROJECT_ROOT}/tests" "${BUNDLE}/tests/" 2>/dev/null || true

# Checksums
(
  cd "${BUNDLE}"
  find . -type f ! -name SHA256SUMS ! -name checksums.txt | sort | xargs sha256sum >manifest/checksums.txt
  cp manifest/checksums.txt checksums/SHA256SUMS
)
log_ok "checksums generated"

# Software manifest enrichment
python3 - <<PY
import yaml
from datetime import datetime, timezone
from pathlib import Path
root = Path("${BUNDLE}")
versions = yaml.safe_load((root / "manifest" / "versions.yml").read_text())
manifest = {
  "generated_at": datetime.now(timezone.utc).isoformat(),
  "bundle_version": versions.get("bundle_version"),
  "profile": "${PROFILE}",
  "registry_dns": "${ZOT_FQDN}",
  "repo_dns": "$(fqdn_of repo)",
  "helm_dns": "$(fqdn_of helm)",
  "note": "All endpoints use DNS names. IPs only in config/network.yml.",
  "versions": versions,
  "classification": "LAB_VERIFIED artifacts — not PRODUCTION READY certification",
}
(root / "manifest" / "SOFTWARE-MANIFEST.yml").write_text(yaml.safe_dump(manifest, sort_keys=False))
(root / "SOFTWARE-MANIFEST.yml").write_text(yaml.safe_dump(manifest, sort_keys=False))
print("[OK] SOFTWARE-MANIFEST.yml")
PY

if [[ -f "${BUNDLE}/manifest/missing-downloads.txt" ]]; then
  log_warn "Some downloads missing — see offline-bundle/manifest/missing-downloads.txt"
fi

log_ok "Offline preparation complete: ${BUNDLE}"
log_info "Next: ./scripts/package-offline-bundle.sh"
