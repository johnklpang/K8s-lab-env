# Prerequisites

## Host (Vagrant)

- VirtualBox
- Vagrant
- Sufficient disk for 5× Rocky 9 VMs (2 vCPU / 2 GB each)

## Internet preparation OPS

- Rocky Linux 9 preferred
- curl, git, python3, podman or skopeo, helm, ansible, zstd

## Offline OPS

- No Internet required after bundle import
- DNS names must resolve via OPS dnsmasq

## LAB account

- Username: `devops`
- Password: `password` (LAB ONLY)

Production must use stronger identity, MFA, bastion access, and disabled root SSH.
