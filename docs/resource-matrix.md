# Resource matrix (LAB vs production guidance)

| Component | Minimum LAB | Recommended Production |
|-----------|-------------|------------------------|
| Kubernetes control plane | 2 vCPU / 2 GB | 4+ vCPU / 8+ GB, 3 nodes HA |
| Kubernetes worker | 2 vCPU / 2 GB | 8+ vCPU / 16+ GB |
| Kafka | Minimal single-node | Dedicated resources |
| OpenSearch | Minimal single-node | Dedicated resources |
| Ceph | Not recommended at LAB size | Dedicated storage nodes |
| Service mesh | Optional | Higher headroom |
| Monitoring | Minimal retention | Higher retention / HA |
| Argo CD | Minimal | HA + proper SSO |
| PostgreSQL | Minimal PVC | Dedicated disk / HA |

Automation reports warnings under LAB pressure and refuses to claim PRODUCTION READY automatically.
