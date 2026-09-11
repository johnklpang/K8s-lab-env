# Offline Import

```bash
./scripts/import-offline-bundle.sh /path/to/k8s-offline-bundle-<version>.tar.zst
```

This verifies the bundle, extracts it, generates inventory/DNS from central config, and prepares local repo endpoints:

- http://zot.lab.example:5000
- http://repo.lab.example:8080/rpm/
- http://helm.lab.example:8081/helm/
