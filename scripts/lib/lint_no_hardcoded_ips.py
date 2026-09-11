#!/usr/bin/env python3
"""Fail if node IPs appear outside the central network allowlist."""
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
allowed = {
    "config/network.yml",
    "scripts/dns/generated/dnsmasq.conf",
    "scripts/dns/generated/hosts",
    "ansible/inventory/hosts.ini",
    "Vagrantfile",
    "ansible/group_vars/all.yml",
}
ip_re = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
skip_dirs = {".git", "state", "logs", "reports", "offline-bundle", "__pycache__", ".vagrant"}
findings: list[str] = []

for path in root.rglob("*"):
    if not path.is_file():
        continue
    if any(p in skip_dirs for p in path.parts):
        continue
    rel = str(path.relative_to(root))
    if rel in allowed:
        continue
    if path.suffix in {".png", ".jpg", ".zst", ".tar", ".gz", ".tgz", ".rpm"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue
    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        for match in ip_re.findall(line):
            if match.startswith("127.") or match in {"0.0.0.0", "255.255.255.255"}:
                continue
            if match.endswith(".0") and "/" in line:
                continue
            findings.append(f"{rel}:{i}: hardcoded IP {match}")

if findings:
    print("[FAIL] Hardcoded IP addresses found outside allowlist:")
    print("\n".join(findings[:50]))
    if len(findings) > 50:
        print(f"... and {len(findings) - 50} more")
    sys.exit(1)

print("[OK] no unexpected hardcoded IPs (DNS names required)")
