#!/usr/bin/env python3
"""Validate YAML files (including multi-document manifests)."""
from __future__ import annotations

import sys
from pathlib import Path

import yaml

root = Path(__file__).resolve().parents[2]
errors: list[str] = []
skip = {".git", "offline-bundle", "state", "logs"}

for path in list(root.rglob("*.yml")) + list(root.rglob("*.yaml")):
    if any(p in path.parts for p in skip):
        continue
    try:
        list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{path}: {exc}")

if errors:
    print("YAML errors:")
    print("\n".join(errors))
    sys.exit(1)

print("[OK] YAML parse")
