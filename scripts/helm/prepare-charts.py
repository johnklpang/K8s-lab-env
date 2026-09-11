#!/usr/bin/env python3
"""Stage Helm chart metadata and values for offline use.

Chart repositories are referenced by DNS name at deploy time (helm.<domain>).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from load_config import build_context  # noqa: E402

CHARTS = {
    "cilium": {"repo": "https://helm.cilium.io/", "chart": "cilium", "version_key": ("cilium", "chart_version")},
    "cert_manager": {"repo": "https://charts.jetstack.io", "chart": "cert-manager", "version_key": ("cert_manager", "chart_version")},
    "ingress": {"repo": "https://kubernetes.github.io/ingress-nginx", "chart": "ingress-nginx", "version_key": ("ingress_nginx", "chart_version")},
    "argocd": {"repo": "https://argoproj.github.io/argo-helm", "chart": "argo-cd", "version_key": ("argocd", "chart_version")},
    "postgres": {"repo": "https://charts.bitnami.com/bitnami", "chart": "postgresql", "version_key": ("postgres", "chart_version")},
    "kafka": {"repo": "https://charts.bitnami.com/bitnami", "chart": "kafka", "version_key": ("kafka", "chart_version")},
    "opensearch": {"repo": "https://opensearch-project.github.io/helm-charts/", "chart": "opensearch", "version_key": ("opensearch", "chart_version")},
    "emqx": {"repo": "https://repos.emqx.io/charts", "chart": "emqx", "version_key": ("emqx", "chart_version")},
    "prometheus": {"repo": "https://prometheus-community.github.io/helm-charts", "chart": "kube-prometheus-stack", "version_key": ("prometheus", "chart_version")},
    "loki": {"repo": "https://grafana.github.io/helm-charts", "chart": "loki", "version_key": ("loki", "chart_version")},
    "opentelemetry": {"repo": "https://open-telemetry.github.io/opentelemetry-helm-charts", "chart": "opentelemetry-collector", "version_key": ("opentelemetry", "chart_version")},
    "ceph": {"repo": "https://charts.rook.io/release", "chart": "rook-ceph", "version_key": ("rook_ceph", "chart_version")},
    "trivy": {"repo": "https://aquasecurity.github.io/helm-charts/", "chart": "trivy", "version_key": ("trivy", "chart_version")},
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="minimal")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    ctx = build_context(profile=args.profile)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    index = []

    for comp, meta in CHARTS.items():
        if not ctx["components"].get(comp):
            continue
        vk = meta["version_key"]
        version = ctx["versions"][vk[0]][vk[1]]
        values_src = ROOT / "charts" / "values" / f"{comp}.yml"
        values_dst = out / f"{comp}-values.yaml"
        if values_src.exists():
            text = values_src.read_text(encoding="utf-8")
            # Substitute DNS placeholders
            text = text.replace("{{ZOT_FQDN}}", ctx["services"]["zot"]["fqdn"])
            text = text.replace("{{LAB_DOMAIN}}", ctx["domain"])
            text = text.replace("{{GRAFANA_FQDN}}", ctx["services"]["grafana"]["fqdn"])
            text = text.replace("{{ARGOCD_FQDN}}", ctx["services"]["argocd"]["fqdn"])
            values_dst.write_text(text, encoding="utf-8")
        else:
            values_dst.write_text(
                f"# values for {comp}\n"
                f"# registry: {ctx['services']['zot']['fqdn']}\n"
                f"global:\n  imageRegistry: {ctx['services']['zot']['fqdn']}\n",
                encoding="utf-8",
            )

        entry = {
            "component": comp,
            "chart": meta["chart"],
            "version": version,
            "source_url": meta["repo"],
            "offline_repo_url": ctx["urls"]["helm"],
            "values_file": str(values_dst.name),
            "checksum": hashlib.sha256(values_dst.read_bytes()).hexdigest(),
        }
        index.append(entry)
        # Record download instruction for Internet prep (helm pull)
        (out / f"{comp}.chart.json").write_text(json.dumps(entry, indent=2) + "\n", encoding="utf-8")

    (out / "index.yml").write_text(yaml.safe_dump({"charts": index, "helm_repo_dns": ctx["services"]["helm"]["fqdn"]}, sort_keys=False), encoding="utf-8")
    print(f"[OK] staged {len(index)} charts for offline Helm repo {ctx['services']['helm']['fqdn']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
