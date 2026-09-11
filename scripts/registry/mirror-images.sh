#!/usr/bin/env bash
# Mirror images into Zot using DNS endpoint (never IP).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

MANIFEST="${PROJECT_ROOT}/offline-bundle/manifest/images.yml"
[[ -f "${MANIFEST}" ]] || die "missing ${MANIFEST} — run discover-images / prepare-offline first"

ZOT_URL="$(url_of zot)"
log_info "Mirroring to ${ZOT_URL}"

if ! command -v skopeo >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  die "skopeo or podman required"
fi

python3 - <<PY
import yaml, subprocess, sys
from pathlib import Path
manifest = yaml.safe_load(Path("${MANIFEST}").read_text())
failed = 0
for img in manifest.get("images", []):
    src = img["source"]
    dst = img["destination"]
    # Ensure docker:// transport
    src_ref = src if src.startswith("docker://") else f"docker://{src}"
    dst_ref = dst if dst.startswith("docker://") else f"docker://{dst}"
    print(f"[INFO] mirror {src} -> {dst}")
    cmd = ["skopeo", "copy", "--dest-tls-verify=false", src_ref, dst_ref]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        # podman fallback
        pull = subprocess.run(["podman", "pull", src])
        if pull.returncode != 0:
            failed += 1
            continue
        tag = subprocess.run(["podman", "tag", src, dst])
        push = subprocess.run(["podman", "push", "--tls-verify=false", dst])
        if push.returncode != 0:
            failed += 1
    except subprocess.CalledProcessError:
        failed += 1
sys.exit(1 if failed else 0)
PY

log_ok "image mirror complete"
