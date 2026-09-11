# Rocky Linux 9 Offline Kubernetes Full-Stack Lab

Air-gapped Kubernetes platform lab: **Vagrant + Ansible + Podman + Zot + Helm**.

**Classification:** LAB VERIFIED tooling and workflows. **Not PRODUCTION READY** by default. Production-oriented settings live in the `production-reference` profile as a **PRODUCTION REFERENCE** only.

## DNS-first (no hardcoded IPs)

All scripts, Ansible roles, Helm values, manifests, and docs use **DNS names**.

| Name | Default FQDN |
|------|----------------|
| OPS | `ops.lab.example` |
| Control plane | `master-01.lab.example` |
| Workers | `worker-01.lab.example` … `worker-03.lab.example` |
| Registry | `zot.lab.example` |
| RPM repo | `repo.lab.example` |
| Helm repo | `helm.lab.example` |

IP addresses are defined **only** in [`config/network.yml`](config/network.yml). Hostnames and domain come from [`config/lab.yml`](config/lab.yml). Everything else is generated:

```bash
python3 scripts/lib/load_config.py --profile minimal --write-generated
```

## Quick workflow

### Internet preparation

```bash
vagrant up ops
vagrant ssh ops
cd /opt/k8s-airgap-cicd-lab
./scripts/prepare/prepare-offline.sh
./scripts/package-offline-bundle.sh
```

Produces `k8s-offline-bundle-<version>.tar.zst`.

### Offline deployment

```bash
vagrant up
# transfer bundle to OPS
./scripts/import-offline-bundle.sh /path/to/k8s-offline-bundle-<version>.tar.zst
./deploy.sh --profile minimal
./test.sh
```

### Day-2

```bash
./diagnose.sh
./backup.sh
./lint.sh
./scripts/prepare/update-offline-bundle.sh   # on Internet OPS
```

## Profiles

| Profile | Intent |
|---------|--------|
| `minimal` | LAB acceptance target |
| `standard` | Broader apps + mesh |
| `storage` | Standard + Rook-Ceph |
| `production-reference` | Reference architecture (not a certification) |

Overrides for one run:

```bash
./deploy.sh --enable kafka,opensearch --disable ceph
```

## Project layout

See [docs/00-overview.md](docs/00-overview.md) and [docs/01-architecture.md](docs/01-architecture.md).

Authoritative docs are one topic per file under [`docs/`](docs/) (`00`–`35`).

## LAB credentials

See [`config/credentials.example.yml`](config/credentials.example.yml). Default LAB user: `devops` / `password`. Production must not use these values.

## Versions

Pinned in [`config/versions.yml`](config/versions.yml). Offline deploy never selects a newer version dynamically.
