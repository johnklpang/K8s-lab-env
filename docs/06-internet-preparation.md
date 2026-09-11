# Internet Preparation

## Purpose

Download and stage all artifacts for air-gapped use.

## Prerequisites

Internet access on OPS; tools from [02-prerequisites.md](02-prerequisites.md).

## Command

```bash
vagrant up ops
vagrant ssh ops
cd /opt/k8s-airgap-cicd-lab
./scripts/prepare/prepare-offline.sh
./scripts/package-offline-bundle.sh
```

## Expected output

`k8s-offline-bundle-<version>.tar.zst` where version comes from `config/versions.yml`.

Registry endpoint recorded as DNS name `zot.lab.example` (not an IP).
