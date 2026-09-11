# Kubernetes

Pinned version: see `config/versions.yml`.

Runtime: containerd (not Docker).

Control plane endpoint uses DNS: `master-01.lab.example:6443`.

Image repository rewritten to `zot.lab.example/registry.k8s.io`.

Idempotent init skips when `/etc/kubernetes/admin.conf` exists.
