# DNS and Naming

## Rule

Use DNS / FQDN everywhere. Do not hardcode IP addresses outside `config/network.yml`.

## Default FQDNs

- ops.lab.example
- master-01.lab.example
- worker-01.lab.example / worker-02.lab.example / worker-03.lab.example
- zot.lab.example / repo.lab.example / helm.lab.example
- grafana.lab.example / argocd.lab.example / postgres.lab.example

## LAB DNS

Preferred: dnsmasq on OPS (`dns.implementation` in `config/lab.yml`).

Generated from central config:

```bash
python3 scripts/lib/load_config.py --write-generated
# writes scripts/dns/generated/dnsmasq.conf and hosts fallback
```

## Validation

```bash
./scripts/validation/test-dns.sh
```
