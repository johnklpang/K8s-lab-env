#!/usr/bin/env bash
# Main deployment entry point for the air-gapped Kubernetes LAB.
# Uses DNS names for all endpoints. IP addresses come only from config/network.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

PROFILE=""
ENABLE_OVERRIDES=""
DISABLE_OVERRIDES=""
STAGE=""
PREFLIGHT_ONLY=0
DRY_RUN=0
export PROFILE ENABLE_OVERRIDES DISABLE_OVERRIDES

usage() {
  cat <<EOF
Usage: ./deploy.sh [options]

Options:
  --profile NAME              minimal|standard|storage|production-reference
  --enable COMP[,COMP...]     temporary enable overrides
  --disable COMP[,COMP...]    temporary disable overrides
  --stage N                   run a single stage (e.g. 40 or 40-kubernetes)
  --preflight                 run preflight checks only
  --dry-run                   show plan without applying
  -h, --help                  show help

Examples:
  ./deploy.sh --profile minimal
  ./deploy.sh --enable kafka,opensearch --disable ceph
  ./deploy.sh --stage 40
  ./deploy.sh --preflight
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --enable) ENABLE_OVERRIDES="$2"; shift 2 ;;
    --disable) DISABLE_OVERRIDES="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --preflight) PREFLIGHT_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

ensure_dirs
LOGFILE="${PROJECT_ROOT}/logs/deploy-$(timestamp).log"
exec > >(tee -a "${LOGFILE}") 2>&1

log_info "Starting deployment"
log_info "project_root=${PROJECT_ROOT}"

PROFILE="${PROFILE:-}"
resolve_config "${PROFILE}" "${ENABLE_OVERRIDES}" "${DISABLE_OVERRIDES}"

# Re-read profile from resolved config if not set
if [[ -z "${PROFILE}" ]]; then
  PROFILE="$(python3 "${CONFIG_LOADER}" --emit json | python3 -c 'import json,sys; print(json.load(sys.stdin)["profile"])')"
fi
export PROFILE

log_info "profile=${PROFILE}"
log_info "zot=$(url_of zot)"
log_info "repo=$(url_of repo)"
log_info "helm=$(url_of helm)"
log_info "ops=$(fqdn_of ops)"

# Validate dependencies
if ! python3 "${CONFIG_LOADER}" --profile "${PROFILE}" \
    --enable "${ENABLE_OVERRIDES}" --disable "${DISABLE_OVERRIDES}" \
    --emit validate-deps; then
  die "Component dependency validation failed"
fi
log_ok "configuration validated"

MODE="$(detect_offline_mode)"
log_info "connectivity_mode=${MODE}"

run_preflight() {
  log_info "stage=00-preflight"
  bash "${PROJECT_ROOT}/scripts/validation/preflight.sh" --profile "${PROFILE}"
  mark_stage "00-preflight" "OK"
}

run_ansible_stage() {
  local stage="$1"
  local playbook="$2"
  if stage_done "${stage}" && [[ -z "${STAGE}" ]]; then
    log_ok "${stage} already completed (state file present)"
    return 0
  fi
  log_info "stage=${stage} playbook=${playbook}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "DRY-RUN: would run ansible-playbook ${playbook}"
    return 0
  fi
  export ANSIBLE_ROLES_PATH="${PROJECT_ROOT}/ansible/roles"
  export ANSIBLE_CONFIG="${PROJECT_ROOT}/ansible/ansible.cfg"
  ansible-playbook \
    -i "${PROJECT_ROOT}/ansible/inventory/hosts.ini" \
    "${PROJECT_ROOT}/ansible/playbooks/${playbook}" \
    --extra-vars "lab_profile=${PROFILE}" \
    --extra-vars "enable_overrides=${ENABLE_OVERRIDES}" \
    --extra-vars "disable_overrides=${DISABLE_OVERRIDES}" \
    --extra-vars "offline_mode=$([[ ${MODE} == offline ]] && echo true || echo false)"
  mark_stage "${stage}" "OK"
  log_ok "${stage} complete"
}

STAGES=(
  "00-preflight:preflight (script)"
  "10-os:10-os.yml"
  "20-repositories:20-repositories.yml"
  "30-container-runtime:30-container-runtime.yml"
  "40-kubernetes:40-kubernetes.yml"
  "50-cni:50-cni.yml"
  "60-storage:60-storage.yml"
  "70-security:70-security.yml"
  "80-platform:80-platform.yml"
  "90-applications:90-applications.yml"
  "95-observability:95-observability.yml"
  "99-validation:99-validation.yml"
)

if [[ "${PREFLIGHT_ONLY}" == "1" ]]; then
  run_preflight
  log_ok "preflight only complete"
  exit 0
fi

run_preflight

normalize_stage() {
  local s="$1"
  case "${s}" in
    00|preflight|00-preflight) echo "00-preflight" ;;
    10|os|10-os) echo "10-os" ;;
    20|repositories|20-repositories) echo "20-repositories" ;;
    30|container-runtime|30-container-runtime) echo "30-container-runtime" ;;
    40|kubernetes|40-kubernetes) echo "40-kubernetes" ;;
    50|cni|50-cni) echo "50-cni" ;;
    60|storage|60-storage) echo "60-storage" ;;
    70|security|70-security) echo "70-security" ;;
    80|platform|80-platform) echo "80-platform" ;;
    90|applications|90-applications) echo "90-applications" ;;
    95|observability|95-observability) echo "95-observability" ;;
    99|validation|99-validation) echo "99-validation" ;;
    *) echo "${s}" ;;
  esac
}

if [[ -n "${STAGE}" ]]; then
  STAGE="$(normalize_stage "${STAGE}")"
fi

for entry in "${STAGES[@]}"; do
  stage="${entry%%:*}"
  playbook="${entry#*:}"
  if [[ -n "${STAGE}" && "${stage}" != "${STAGE}" ]]; then
    continue
  fi
  if [[ "${stage}" == "00-preflight" ]]; then
    continue
  fi
  run_ansible_stage "${stage}" "${playbook}"
done

# Deployment report
REPORT="${PROJECT_ROOT}/reports/deployment-report.yml"
python3 - <<PY
import json, yaml
from pathlib import Path
from datetime import datetime, timezone
root = Path("${PROJECT_ROOT}")
ctx = json.loads((root / "state" / "resolved-config.json").read_text())
components = {k: v for k, v in ctx["components"].items() if isinstance(v, bool)}
enabled = sorted([k for k, v in components.items() if v])
disabled = sorted([k for k, v in components.items() if not v])
report = {
  "generated_at": datetime.now(timezone.utc).isoformat(),
  "profile": ctx["profile"],
  "classification": ctx["components"].get("profile_meta", {}).get("classification", "LAB_VERIFIED"),
  "production_ready": False,
  "domain": ctx["domain"],
  "endpoints": {
    "ops": ctx["fqdns"]["ops"],
    "zot": ctx["urls"]["zot"],
    "repo": ctx["urls"]["repo"],
    "helm": ctx["urls"]["helm"],
  },
  "enabled_components": enabled,
  "skipped_components": disabled,
  "versions": {
    "bundle": ctx["versions"].get("bundle_version"),
    "kubernetes": ctx["versions"]["kubernetes"]["version"],
    "cilium": ctx["versions"]["cilium"]["version"],
  },
  "notes": [
    "All service endpoints use DNS names (no hardcoded IPs in deployment logic).",
    "Disabled components are SKIPPED, not FAILED.",
    "This report does not certify PRODUCTION READY status.",
  ],
}
(root / "reports" / "deployment-report.yml").write_text(yaml.safe_dump(report, sort_keys=False))
text = [
  "Deployment Report",
  "=================",
  f"Profile: {report['profile']}",
  f"Classification: {report['classification']}",
  f"Domain: {report['domain']}",
  f"Zot: {report['endpoints']['zot']}",
  f"Repo: {report['endpoints']['repo']}",
  f"Helm: {report['endpoints']['helm']}",
  "",
  "Enabled: " + ", ".join(enabled),
  "Skipped: " + ", ".join(disabled),
  "",
  "PRODUCTION READY: false",
]
(root / "reports" / "deployment-report.txt").write_text("\\n".join(text) + "\\n")
print("[OK] wrote reports/deployment-report.yml")
PY

log_ok "deployment finished — see ${LOGFILE} and reports/deployment-report.txt"
