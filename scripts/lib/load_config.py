#!/usr/bin/env python3
"""Load central LAB configuration and emit DNS-first derived values.

IP addresses are read ONLY from config/network.yml.
All consumers should prefer FQDNs from this module.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip3 install pyyaml", file=sys.stderr)
    sys.exit(2)


def project_root() -> Path:
    env = os.environ.get("PROJECT_ROOT")
    if env:
        return Path(env).resolve()
    # scripts/lib/load_config.py -> repo root
    return Path(__file__).resolve().parents[2]


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Missing config: {path}")
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Expected mapping in {path}")
    return data


def fqdn(hostname: str, domain: str) -> str:
    hostname = hostname.strip()
    domain = domain.strip()
    if hostname.endswith("." + domain) or hostname == domain:
        return hostname
    return f"{hostname}.{domain}"


def merge_components(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in overlay.items():
        if key == "profile_meta" or key == "dependencies":
            out[key] = value
            continue
        if isinstance(value, bool) or value is None or isinstance(value, (str, int, float)):
            out[key] = value
    return out


def apply_overrides(components: dict[str, Any], enable: list[str], disable: list[str]) -> dict[str, Any]:
    out = dict(components)
    for name in enable:
        name = name.strip().replace("-", "_")
        if name:
            out[name] = True
    for name in disable:
        name = name.strip().replace("-", "_")
        if name:
            out[name] = False
    return out


def build_context(
    profile: str | None = None,
    enable: list[str] | None = None,
    disable: list[str] | None = None,
) -> dict[str, Any]:
    root = project_root()
    lab = load_yaml(root / "config" / "lab.yml")
    network = load_yaml(root / "config" / "network.yml")
    components = load_yaml(root / "config" / "components.yml")
    versions = load_yaml(root / "config" / "versions.yml")

    domain = lab["lab_domain"]
    profile_name = profile or lab.get("default_profile", "minimal")
    profile_path = root / "config" / "profiles" / f"{profile_name}.yml"
    if profile_path.exists():
        components = merge_components(components, load_yaml(profile_path))

    components = apply_overrides(components, enable or [], disable or [])

    nodes = {}
    for key, node in network.get("nodes", {}).items():
        host = node["hostname"]
        nodes[key] = {
            "hostname": host,
            "fqdn": fqdn(host, domain),
            "ip": node["ip"],
            "role": "ops" if key == "ops" else ("control_plane" if key.startswith("master") else "worker"),
        }

    services = {}
    for svc, short in lab.get("service_hostnames", {}).items():
        svc_net = network.get("services", {}).get(svc, {})
        svc_fqdn = fqdn(short, domain)
        port = svc_net.get("port")
        scheme = svc_net.get("scheme", "http")
        path = svc_net.get("path", "")
        url = f"{scheme}://{svc_fqdn}"
        if port and port not in (80, 443):
            url = f"{scheme}://{svc_fqdn}:{port}"
        if path:
            url = url.rstrip("/") + path
        services[svc] = {
            "hostname": short,
            "fqdn": svc_fqdn,
            "port": port,
            "scheme": scheme,
            "path": path,
            "url": url,
            "bind_host": svc_net.get("bind_host", "ops"),
        }

    # DNS A records: node FQDNs + service FQDNs (services that bind to ops resolve to ops IP)
    dns_records = []
    for node in nodes.values():
        dns_records.append({"name": node["fqdn"], "type": "A", "value": node["ip"]})
        dns_records.append({"name": node["hostname"], "type": "A", "value": node["ip"]})

    ops_ip = nodes["ops"]["ip"]
    for svc, meta in services.items():
        bind = meta.get("bind_host", "ops")
        ip = nodes.get(bind, nodes["ops"])["ip"] if bind in nodes else ops_ip
        dns_records.append({"name": meta["fqdn"], "type": "A", "value": ip})
        dns_records.append({"name": meta["hostname"], "type": "A", "value": ip})

    # Deduplicate records by name+type
    seen = set()
    unique_records = []
    for rec in dns_records:
        key = (rec["name"], rec["type"])
        if key in seen:
            continue
        seen.add(key)
        unique_records.append(rec)

    creds_path = root / "config" / "credentials.yml"
    if not creds_path.exists():
        creds_path = root / "config" / "credentials.example.yml"
    credentials = load_yaml(creds_path) if creds_path.exists() else {}

    return {
        "project_root": str(root),
        "lab": lab,
        "network": network,
        "components": components,
        "versions": versions,
        "credentials": credentials,
        "domain": domain,
        "profile": profile_name,
        "nodes": nodes,
        "services": services,
        "dns_records": unique_records,
        "fqdns": {
            "ops": nodes["ops"]["fqdn"],
            "master": nodes[lab["master_hostname"]]["fqdn"],
            "workers": [nodes[w]["fqdn"] for w in lab["worker_hostnames"]],
            "zot": services["zot"]["fqdn"],
            "repo": services["repo"]["fqdn"],
            "helm": services["helm"]["fqdn"],
        },
        "urls": {
            "zot": services["zot"]["url"],
            "repo": services["repo"]["url"],
            "helm": services["helm"]["url"],
        },
    }


def emit_ansible_inventory(ctx: dict[str, Any]) -> str:
    lines = [
        "# GENERATED from config/lab.yml + config/network.yml — do not edit by hand",
        "# Access nodes by DNS/FQDN. ansible_host uses FQDN; IPs come only from network.yml.",
        "",
        "[ops]",
        f"{ctx['nodes']['ops']['fqdn']} ansible_host={ctx['nodes']['ops']['fqdn']} node_ip={ctx['nodes']['ops']['ip']}",
        "",
        "[masters]",
    ]
    master = ctx["lab"]["master_hostname"]
    m = ctx["nodes"][master]
    lines.append(f"{m['fqdn']} ansible_host={m['fqdn']} node_ip={m['ip']}")
    lines.extend(["", "[workers]"])
    for wh in ctx["lab"]["worker_hostnames"]:
        w = ctx["nodes"][wh]
        lines.append(f"{w['fqdn']} ansible_host={w['fqdn']} node_ip={w['ip']}")
    lines.extend(
        [
            "",
            "[k8s:children]",
            "masters",
            "workers",
            "",
            "[all:vars]",
            f"lab_domain={ctx['domain']}",
            f"zot_fqdn={ctx['services']['zot']['fqdn']}",
            f"repo_fqdn={ctx['services']['repo']['fqdn']}",
            f"helm_fqdn={ctx['services']['helm']['fqdn']}",
            f"dns_server_fqdn={ctx['nodes']['ops']['fqdn']}",
            f"ansible_user={ctx['lab']['lab_user']['username']}",
            "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'",
            "",
        ]
    )
    return "\n".join(lines)


def emit_dnsmasq(ctx: dict[str, Any]) -> str:
    lines = [
        "# GENERATED from central config — do not edit by hand",
        f"domain={ctx['domain']}",
        "expand-hosts",
        "local=/" + ctx["domain"] + "/",
        f"listen-address={ctx['nodes']['ops']['ip']}",
        "bind-interfaces",
        "no-resolv",
        "",
    ]
    for rec in ctx["dns_records"]:
        if rec["type"] == "A":
            lines.append(f"address=/{rec['name']}/{rec['value']}")
    # PTR records for reverse resolution
    lines.append("")
    for key, node in ctx["nodes"].items():
        ip = node["ip"]
        # simple in-addr for /24
        octets = ip.split(".")
        if len(octets) == 4:
            ptr = f"{octets[3]}.{octets[2]}.{octets[1]}.{octets[0]}.in-addr.arpa"
            lines.append(f"ptr-record={ptr},{node['fqdn']}")
    return "\n".join(lines) + "\n"


def emit_hosts(ctx: dict[str, Any]) -> str:
    lines = [
        "# GENERATED from config/lab.yml + config/network.yml — hosts fallback only",
        "# Prefer dnsmasq/CoreDNS; do not maintain this file manually.",
        "127.0.0.1   localhost localhost.localdomain",
        "::1         localhost localhost.localdomain",
        "",
    ]
    emitted = set()
    for rec in ctx["dns_records"]:
        if rec["type"] != "A":
            continue
        key = (rec["value"], rec["name"])
        if key in emitted:
            continue
        emitted.add(key)
        lines.append(f"{rec['value']}   {rec['name']}")
    return "\n".join(lines) + "\n"


def emit_group_vars(ctx: dict[str, Any]) -> str:
    data = {
        "lab_domain": ctx["domain"],
        "lab_profile": ctx["profile"],
        "lab_user": ctx["lab"]["lab_user"]["username"],
        "lab_dns_hosts_fallback": ctx["lab"].get("dns", {}).get("hosts_fallback", True),
        "lab_classification": ctx["components"].get("profile_meta", {}).get(
            "classification", ctx["lab"]["classification"]["lab"]
        ),
        "ops_fqdn": ctx["fqdns"]["ops"],
        "master_fqdn": ctx["fqdns"]["master"],
        "worker_fqdns": ctx["fqdns"]["workers"],
        "zot_fqdn": ctx["fqdns"]["zot"],
        "zot_url": ctx["urls"]["zot"],
        "repo_fqdn": ctx["fqdns"]["repo"],
        "repo_url": ctx["urls"]["repo"],
        "helm_fqdn": ctx["fqdns"]["helm"],
        "helm_url": ctx["urls"]["helm"],
        "dns_server_fqdn": ctx["fqdns"]["ops"],
        "components": {k: v for k, v in ctx["components"].items() if isinstance(v, bool)},
        "versions": ctx["versions"],
        "kubernetes_pod_cidr": ctx["network"]["kubernetes"]["pod_cidr"],
        "kubernetes_service_cidr": ctx["network"]["kubernetes"]["service_cidr"],
        "kubernetes_cluster_dns": ctx["network"]["kubernetes"]["cluster_dns"],
        "service_fqdns": {k: v["fqdn"] for k, v in ctx["services"].items()},
        "ports": ctx["network"].get("ports", {}),
        # node_ip map keyed by FQDN — only place roles may learn IPs (from network.yml)
        "node_ips_by_fqdn": {n["fqdn"]: n["ip"] for n in ctx["nodes"].values()},
    }
    return yaml.safe_dump(data, default_flow_style=False, sort_keys=False)


def validate_no_ip_leak(paths: list[Path], allowed_files: set[str]) -> list[str]:
    """Scan project for literal IPv4 outside allowlisted files."""
    import re

    ip_re = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
    # Allow RFC1918 documentation examples in network.yml and generated files
    findings = []
    skip_dirs = {".git", "state", "logs", "reports", "offline-bundle", "__pycache__", ".vagrant"}
    for base in paths:
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if any(part in skip_dirs for part in path.parts):
                continue
            rel = str(path.relative_to(project_root()))
            if rel in allowed_files or path.name.endswith((".png", ".jpg", ".zst", ".tar", ".gz")):
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if line.strip().startswith("#"):
                    continue
                for match in ip_re.findall(line):
                    # allow localhost and kubernetes service CIDR docs that are CIDRs not hosts
                    if match.startswith("127.") or match.endswith(".0") or match.endswith(".255"):
                        continue
                    if match in ("0.0.0.0", "255.255.255.255"):
                        continue
                    findings.append(f"{rel}:{i}: {match}")
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Load and emit LAB configuration")
    parser.add_argument("--profile", default=None)
    parser.add_argument("--enable", default="", help="Comma-separated components to enable")
    parser.add_argument("--disable", default="", help="Comma-separated components to disable")
    parser.add_argument(
        "--emit",
        choices=["json", "inventory", "dnsmasq", "hosts", "group_vars", "fqdn", "url", "validate-deps"],
        default="json",
    )
    parser.add_argument("--name", default="", help="For fqdn/url emit: service or node name")
    parser.add_argument("--write-generated", action="store_true", help="Write generated inventory/dns/hosts")
    args = parser.parse_args()

    enable = [x for x in args.enable.split(",") if x.strip()]
    disable = [x for x in args.disable.split(",") if x.strip()]
    ctx = build_context(profile=args.profile, enable=enable, disable=disable)

    if args.write_generated:
        root = project_root()
        gen = root / "ansible" / "inventory"
        gen.mkdir(parents=True, exist_ok=True)
        (gen / "hosts.ini").write_text(emit_ansible_inventory(ctx), encoding="utf-8")
        gv = root / "ansible" / "group_vars"
        gv.mkdir(parents=True, exist_ok=True)
        (gv / "all.yml").write_text(emit_group_vars(ctx), encoding="utf-8")
        dns_dir = root / "scripts" / "dns" / "generated"
        dns_dir.mkdir(parents=True, exist_ok=True)
        (dns_dir / "dnsmasq.conf").write_text(emit_dnsmasq(ctx), encoding="utf-8")
        (dns_dir / "hosts").write_text(emit_hosts(ctx), encoding="utf-8")
        state = root / "state"
        state.mkdir(parents=True, exist_ok=True)
        (state / "resolved-config.json").write_text(json.dumps(ctx, indent=2, default=str), encoding="utf-8")
        print(f"[OK] wrote generated inventory, group_vars, DNS, and state for profile={ctx['profile']}")

    if args.emit == "json":
        # Strip credentials from default stdout dump
        safe = dict(ctx)
        safe["credentials"] = {"present": bool(ctx.get("credentials")), "lab_only": True}
        print(json.dumps(safe, indent=2, default=str))
    elif args.emit == "inventory":
        print(emit_ansible_inventory(ctx))
    elif args.emit == "dnsmasq":
        print(emit_dnsmasq(ctx))
    elif args.emit == "hosts":
        print(emit_hosts(ctx))
    elif args.emit == "group_vars":
        print(emit_group_vars(ctx))
    elif args.emit == "fqdn":
        name = args.name
        if name in ctx["nodes"]:
            print(ctx["nodes"][name]["fqdn"])
        elif name in ctx["services"]:
            print(ctx["services"][name]["fqdn"])
        else:
            print(fqdn(name, ctx["domain"]))
    elif args.emit == "url":
        name = args.name
        if name not in ctx["services"]:
            print(f"Unknown service: {name}", file=sys.stderr)
            return 1
        print(ctx["services"][name]["url"])
    elif args.emit == "validate-deps":
        errors = []
        warnings = []
        c = ctx["components"]
        deps = c.get("dependencies") or load_yaml(project_root() / "config" / "components.yml").get("dependencies", {})
        for comp, rule in deps.items():
            if not c.get(comp):
                continue
            req_any = rule.get("requires_any_of", [])
            if req_any and not any(c.get(r) for r in req_any):
                errors.append(f"{comp} requires one of: {', '.join(req_any)}")
            req_all = rule.get("requires_all_of", [])
            for r in req_all:
                if not c.get(r):
                    errors.append(f"{comp} requires {r}")
            if rule.get("min_memory_mb_warn"):
                warnings.append(
                    f"{comp}: LAB nodes may be under-resourced (warn threshold {rule['min_memory_mb_warn']} MB)"
                )
        for w in warnings:
            print(f"[WARN] {w}")
        for e in errors:
            print(f"[ERROR] {e}")
        return 1 if errors else 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
