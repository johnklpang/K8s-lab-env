#!/usr/bin/env bash
# Shared helpers for the air-gapped Kubernetes LAB.
# Prefer DNS/FQDN names. Never hardcode IP addresses in callers.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
PROJECT_ROOT="$(cd "${LIB_DIR}/../.." && pwd)"
export PROJECT_ROOT

CONFIG_LOADER="${LIB_DIR}/load_config.py"

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${level}" "$*"
}

log_info() { log INFO "$@"; }
log_ok() { log OK "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_skip() { log SKIP "$@"; }

die() {
  log_error "$@"
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

ensure_dirs() {
  mkdir -p "${PROJECT_ROOT}/"{logs,reports,state,offline-bundle/manifest}
}

timestamp() {
  date -u +'%Y-%m-%d-%H%M%S'
}

# Load resolved config JSON into env helpers
resolve_config() {
  local profile="${1:-}"
  local enable="${2:-}"
  local disable="${3:-}"
  local args=()
  [[ -n "${profile}" ]] && args+=(--profile "${profile}")
  [[ -n "${enable}" ]] && args+=(--enable "${enable}")
  [[ -n "${disable}" ]] && args+=(--disable "${disable}")
  python3 "${CONFIG_LOADER}" "${args[@]}" --write-generated >/dev/null
}

fqdn_of() {
  local name="$1"
  local profile="${PROFILE:-}"
  local args=(--emit fqdn --name "${name}")
  [[ -n "${profile}" ]] && args+=(--profile "${profile}")
  python3 "${CONFIG_LOADER}" "${args[@]}"
}

url_of() {
  local name="$1"
  local profile="${PROFILE:-}"
  local args=(--emit url --name "${name}")
  [[ -n "${profile}" ]] && args+=(--profile "${profile}")
  python3 "${CONFIG_LOADER}" "${args[@]}"
}

lab_domain() {
  python3 "${CONFIG_LOADER}" --emit json | python3 -c 'import json,sys; print(json.load(sys.stdin)["domain"])'
}

component_enabled() {
  local name="$1"
  local profile="${PROFILE:-}"
  local args=(--emit json)
  [[ -n "${profile}" ]] && args+=(--profile "${profile}")
  [[ -n "${ENABLE_OVERRIDES:-}" ]] && args+=(--enable "${ENABLE_OVERRIDES}")
  [[ -n "${DISABLE_OVERRIDES:-}" ]] && args+=(--disable "${DISABLE_OVERRIDES}")
  python3 "${CONFIG_LOADER}" "${args[@]}" | python3 -c "import json,sys; c=json.load(sys.stdin)['components']; sys.exit(0 if c.get('${name}'.replace('-', '_'), False) else 1)"
}

detect_offline_mode() {
  # Offline if we cannot reach a well-known external host OR OFFLINE_MODE=1
  if [[ "${OFFLINE_MODE:-0}" == "1" ]]; then
    echo "offline"
    return
  fi
  if ! getent hosts "${OFFLINE_PROBE_HOST:-example.com}" >/dev/null 2>&1; then
    echo "offline"
    return
  fi
  # Secondary connectivity probe (may fail in air-gap)
  if ! curl -fsS --connect-timeout 2 "https://example.com" >/dev/null 2>&1; then
    echo "offline"
    return
  fi
  echo "online"
}

stage_file() {
  echo "${PROJECT_ROOT}/state/stages/${1}.status"
}

mark_stage() {
  local stage="$1"
  local status="$2"
  mkdir -p "${PROJECT_ROOT}/state/stages"
  printf '%s %s\n' "$(timestamp)" "${status}" >"$(stage_file "${stage}")"
}

stage_done() {
  local stage="$1"
  local f
  f="$(stage_file "${stage}")"
  [[ -f "${f}" ]] && grep -q ' OK$' "${f}"
}

run_logged() {
  local logfile="$1"
  shift
  log_info "RUN: $*"
  "$@" >>"${logfile}" 2>&1
}
