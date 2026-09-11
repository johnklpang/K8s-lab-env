#!/usr/bin/env python3
"""Discover required container images for the selected profile.

Destinations always use the Zot DNS name (zot.<domain>), never IP addresses.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from load_config import build_context  # noqa: E402


# Base images always required for Kubernetes + Cilium LAB
BASE_IMAGES = [
    ("kubernetes", "registry.k8s.io/kube-apiserver", "{k8s}"),
    ("kubernetes", "registry.k8s.io/kube-controller-manager", "{k8s}"),
    ("kubernetes", "registry.k8s.io/kube-scheduler", "{k8s}"),
    ("kubernetes", "registry.k8s.io/kube-proxy", "{k8s}"),
    ("kubernetes", "registry.k8s.io/coredns/coredns", "v{coredns}"),
    ("kubernetes", "registry.k8s.io/etcd", "3.5.15-0"),
    ("kubernetes", "registry.k8s.io/pause", "{pause}"),
    ("cilium", "quay.io/cilium/cilium", "v{cilium}"),
    ("cilium", "quay.io/cilium/operator-generic", "v{cilium}"),
    ("hubble", "quay.io/cilium/hubble-relay", "v{cilium}"),
    ("hubble", "quay.io/cilium/hubble-ui", "v{hubble_ui}"),
    ("hubble", "quay.io/cilium/hubble-ui-backend", "v{hubble_ui}"),
]

OPTIONAL = {
    "cert_manager": [
        ("quay.io/jetstack/cert-manager-controller", "v{cert_manager}"),
        ("quay.io/jetstack/cert-manager-webhook", "v{cert_manager}"),
        ("quay.io/jetstack/cert-manager-cainjector", "v{cert_manager}"),
    ],
    "ingress": [
        ("registry.k8s.io/ingress-nginx/controller", "v{ingress}"),
    ],
    "postgres": [
        ("docker.io/bitnami/postgresql", "{postgres}"),
    ],
    "prometheus": [
        ("quay.io/prometheus/prometheus", "v{prometheus}"),
        ("quay.io/prometheus-operator/prometheus-operator", "v0.77.1"),
    ],
    "grafana": [
        ("docker.io/grafana/grafana", "{grafana}"),
    ],
    "argocd": [
        ("quay.io/argoproj/argocd", "v{argocd}"),
    ],
    "kafka": [
        ("docker.io/bitnami/kafka", "{kafka}"),
    ],
    "opensearch": [
        ("docker.io/opensearchproject/opensearch", "{opensearch}"),
        ("docker.io/opensearchproject/opensearch-dashboards", "{opensearch}"),
    ],
    "emqx": [
        ("docker.io/emqx/emqx", "{emqx}"),
    ],
    "loki": [
        ("docker.io/grafana/loki", "{loki}"),
    ],
    "opentelemetry": [
        ("docker.io/otel/opentelemetry-collector-contrib", "{otel}"),
    ],
    "service_mesh": [
        ("docker.io/istio/pilot", "{istio}"),
        ("docker.io/istio/proxyv2", "{istio}"),
    ],
    "ceph": [
        ("docker.io/rook/ceph", "v{rook}"),
        ("quay.io/ceph/ceph", "v18.2.4"),
    ],
    "trivy": [
        ("docker.io/aquasec/trivy", "{trivy}"),
    ],
    "storage_local_path": [
        ("docker.io/rancher/local-path-provisioner", "v{local_path}"),
    ],
}


def fmt(template: str, versions: dict) -> str:
    return template.format(
        k8s="v" + versions["kubernetes"]["version"],
        coredns=versions["coredns"]["version"],
        pause=versions["pause_image"]["version"],
        cilium=versions["cilium"]["version"],
        hubble_ui=versions["hubble"]["ui_version"],
        cert_manager=versions["cert_manager"]["version"],
        ingress=versions["ingress_nginx"]["version"],
        postgres=versions["postgres"]["version"],
        prometheus=versions["prometheus"]["version"],
        grafana=versions["grafana"]["version"],
        argocd=versions["argocd"]["version"],
        kafka=versions["kafka"]["version"],
        opensearch=versions["opensearch"]["version"],
        emqx=versions["emqx"]["version"],
        loki=versions["loki"]["version"],
        otel=versions["opentelemetry"]["version"],
        istio=versions["istio"]["version"],
        rook=versions["rook_ceph"]["version"],
        trivy=versions["trivy"]["version"],
        local_path=versions["local_path_provisioner"]["version"],
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="minimal")
    parser.add_argument("--out-yml", required=True)
    parser.add_argument("--out-txt", required=True)
    args = parser.parse_args()

    ctx = build_context(profile=args.profile)
    versions = ctx["versions"]
    zot = ctx["services"]["zot"]["fqdn"]
    components = ctx["components"]

    records = []
    for component, repo, tag_t in BASE_IMAGES:
        if component == "hubble" and not components.get("hubble", True):
            continue
        tag = fmt(tag_t, versions)
        dest_repo = f"{zot}/{repo}"
        records.append(
            {
                "source": f"{repo}:{tag}",
                "destination": f"{dest_repo}:{tag}",
                "repository": repo,
                "tag": tag,
                "digest": "",  # filled after pull
                "component": component,
                "version": tag.lstrip("v"),
                "architecture": versions.get("architecture", "x86_64"),
            }
        )

    for comp, images in OPTIONAL.items():
        if not components.get(comp):
            continue
        for repo, tag_t in images:
            tag = fmt(tag_t, versions)
            dest_repo = f"{zot}/{repo}"
            records.append(
                {
                    "source": f"{repo}:{tag}",
                    "destination": f"{dest_repo}:{tag}",
                    "repository": repo,
                    "tag": tag,
                    "digest": "",
                    "component": comp,
                    "version": tag.lstrip("v"),
                    "architecture": versions.get("architecture", "x86_64"),
                }
            )

    out = {
        "registry_fqdn": zot,
        "registry_url": ctx["urls"]["zot"],
        "profile": args.profile,
        "note": "Destinations use DNS names only. Prefer digest pins after mirroring.",
        "images": records,
    }
    Path(args.out_yml).write_text(yaml.safe_dump(out, sort_keys=False), encoding="utf-8")
    Path(args.out_txt).write_text("\n".join(r["source"] for r in records) + "\n", encoding="utf-8")
    print(f"[OK] discovered {len(records)} images -> {args.out_yml}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
