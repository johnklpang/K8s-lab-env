# Upgrade

1. Update `config/versions.yml` on Internet OPS
2. `./scripts/prepare/update-offline-bundle.sh`
3. Transfer + import on offline OPS
4. Stage upgrades via `./deploy.sh --stage <N>`

Never let offline nodes pull newer versions from the Internet.
