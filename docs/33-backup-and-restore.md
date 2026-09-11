# Backup and Restore

```bash
./backup.sh
CONFIRM_RESTORE=yes ./restore.sh reports/backup-<timestamp>.tar.gz
```

etcd restore is performed on the control-plane FQDN (`master-01.lab.example`).

PostgreSQL uses `postgres.database.svc.cluster.local`.
