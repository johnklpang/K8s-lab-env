# Configuration

Single source of truth:

```
config/
  lab.yml          # names, domain, DNS implementation
  network.yml      # ONLY place node IPs are defined
  components.yml   # enable/disable defaults
  versions.yml     # pinned versions
  credentials.example.yml
  profiles/
```

## Change domain

Edit `lab_domain` in `config/lab.yml`, then regenerate:

```bash
python3 scripts/lib/load_config.py --profile minimal --write-generated
```

## Change IPs

Edit `config/network.yml` only. Never copy IPs into roles, Helm values, or docs.

## Profiles and overrides

```bash
./deploy.sh --profile minimal
./deploy.sh --enable kafka,opensearch --disable ceph
```
