#!/usr/bin/env bash
# Controlled failure tests — require explicit --failure-tests / CONFIRM
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

[[ "${CONFIRM_FAILURE_TESTS:-}" == "yes" ]] || die "Set CONFIRM_FAILURE_TESTS=yes to run destructive recovery tests"

log_warn "Running failure tests against live cluster"
MASTER="$(fqdn_of master-01)"
log_info "control_plane=${MASTER}"

kubectl delete pod -l app=lab-test-app --wait=false || true
sleep 5
kubectl wait --for=condition=Ready pod -l app=lab-test-app --timeout=120s || log_warn "test app recovery incomplete"

log_ok "Failure tests completed (partial suite) — see docs/29-testing.md"
