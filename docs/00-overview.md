# Overview

Rocky Linux 9 offline Kubernetes full-stack LAB using Vagrant, Ansible, Podman, Zot, Helm, and air-gapped deployment.

## Classification

| Label | Meaning |
|-------|---------|
| LAB VERIFIED | Exercised in this LAB topology |
| PRODUCTION REFERENCE | Architecture guidance only |
| PRODUCTION READY | **Not claimed** by this project by default |

## Workflow

```
Internet OPS → prepare-offline.sh → package-offline-bundle.sh
        → secure transfer → offline OPS
        → import-offline-bundle.sh → deploy.sh → test.sh
```

## DNS-first rule

All endpoints use DNS names from `config/lab.yml` (for example `zot.lab.example`).
IP addresses exist only in `config/network.yml` and files generated from it.

## Main commands

See [README.md](../README.md) and [03-configuration.md](03-configuration.md).
