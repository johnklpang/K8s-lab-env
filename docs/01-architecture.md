# Architecture

## Nodes (LAB)

| Role | FQDN (default domain) |
|------|------------------------|
| OPS | ops.lab.example |
| Control plane | master-01.lab.example |
| Workers | worker-01.lab.example, worker-02.lab.example, worker-03.lab.example |

## Services on OPS

| Service | FQDN | Purpose |
|---------|------|---------|
| DNS (dnsmasq) | ops.lab.example | Lab DNS |
| Zot | zot.lab.example | OCI registry |
| RPM repo | repo.lab.example | Offline RPMs |
| Helm repo | helm.lab.example | Offline charts |

## Component dependency diagram

```
containerd → kubernetes → cilium/hubble → storage
                              ↓
                        cert-manager → ingress
                              ↓
              platform (mesh?, argocd?) + apps + observability
```

## Profiles

- **minimal** — LAB VERIFIED acceptance target
- **standard** — adds mesh/apps/observability extras
- **storage** — standard + Rook-Ceph
- **production-reference** — HA-oriented reference (not certification)
