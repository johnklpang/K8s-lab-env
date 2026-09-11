#!/usr/bin/env bash
# Lint shell, YAML, Ansible, and configuration. Fail on hardcoded IPs outside allowlist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

ensure_dirs
ERR=0

log_info "Lint starting"

# ShellCheck
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t SHELL_FILES < <(find "${PROJECT_ROOT}" -type f -name '*.sh' ! -path '*/.git/*' ! -path '*/offline-bundle/*')
  if [[ ${#SHELL_FILES[@]} -gt 0 ]]; then
    shellcheck -x "${SHELL_FILES[@]}" || ERR=1
  fi
  log_ok "shellcheck complete"
else
  log_warn "shellcheck not installed — skipped"
fi

# YAML parse (supports multi-doc manifests)
if ! python3 "${PROJECT_ROOT}/scripts/lib/lint_yaml.py"; then
  ERR=1
fi

# Ansible syntax
if command -v ansible-playbook >/dev/null 2>&1; then
  resolve_config "${PROFILE:-minimal}" || true
  export ANSIBLE_ROLES_PATH="${PROJECT_ROOT}/ansible/roles"
  export ANSIBLE_CONFIG="${PROJECT_ROOT}/ansible/ansible.cfg"
  for pb in "${PROJECT_ROOT}"/ansible/playbooks/*.yml; do
    [[ -f "${pb}" ]] || continue
    ansible-playbook -i "${PROJECT_ROOT}/ansible/inventory/hosts.ini" --syntax-check "${pb}" || ERR=1
  done
  log_ok "ansible syntax check"
else
  log_warn "ansible-playbook not installed — skipped"
fi

if command -v ansible-lint >/dev/null 2>&1; then
  ansible-lint "${PROJECT_ROOT}/ansible" || ERR=1
else
  log_warn "ansible-lint not installed — skipped"
fi

# Hardcoded IP scan
if ! python3 "${PROJECT_ROOT}/scripts/lib/lint_no_hardcoded_ips.py"; then
  ERR=1
fi

# Config loader self-test
python3 "${CONFIG_LOADER}" --profile minimal --write-generated >/dev/null
python3 "${CONFIG_LOADER}" --profile minimal --emit validate-deps
log_ok "config loader"

if [[ "${ERR}" -ne 0 ]]; then
  die "lint failed"
fi
log_ok "lint passed"
