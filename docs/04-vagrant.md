# Vagrant

## Purpose

Create Rocky Linux 9 VMs for OPS and the Kubernetes cluster.

## Commands

```bash
vagrant up
vagrant status
vagrant ssh ops
vagrant ssh master-01
vagrant halt
vagrant destroy
```

Hostnames and private IPs are loaded from `config/lab.yml` and `config/network.yml`.

Offline box mode:

```bash
VAGRANT_OFFLINE=1 vagrant up
```

Deployment logic belongs in Ansible, not the Vagrantfile.
