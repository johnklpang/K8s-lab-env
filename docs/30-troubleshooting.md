# Troubleshooting

```bash
./diagnose.sh
```

Creates `reports/diagnostic-<timestamp>.tar.gz`.

Check DNS first: `./scripts/validation/test-dns.sh`.

Confirm registry via DNS: `curl http://zot.lab.example:5000/v2/`.
