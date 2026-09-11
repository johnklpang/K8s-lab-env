# frozen_string_literal: true

# Vagrant LAB topology for Rocky Linux 9 air-gapped Kubernetes.
# Hostnames, FQDNs, and IPs are loaded from config/lab.yml + config/network.yml.
# Do not duplicate network values here.

require 'yaml'
require 'pathname'

ROOT = Pathname.new(__dir__).expand_path
LAB = YAML.load_file(ROOT.join('config/lab.yml'))
NET = YAML.load_file(ROOT.join('config/network.yml'))

DOMAIN = LAB.fetch('lab_domain')
NODES = NET.fetch('nodes')
OFFLINE = ENV.fetch('VAGRANT_OFFLINE', '0') == '1'

def fqdn(hostname)
  return hostname if hostname.end_with?(".#{DOMAIN}")
  "#{hostname}.#{DOMAIN}"
end

def node_ip(key)
  NODES.fetch(key).fetch('ip')
end

def node_hostname(key)
  NODES.fetch(key).fetch('hostname')
end

# LAB credentials — production must not use these
LAB_USER = 'devops'
LAB_PASSWORD = 'password'

BOX = 'rockylinux/9'

Vagrant.configure('2') do |config|
  config.vm.box = BOX
  config.vm.box_check_update = !OFFLINE

  # Shared project mount
  config.vm.synced_folder '.', '/opt/k8s-airgap-cicd-lab', type: 'virtualbox'

  NODES.each do |key, node|
    hostname = node.fetch('hostname')
    ip = node.fetch('ip')
    full = fqdn(hostname)

    config.vm.define hostname do |node_cfg|
      node_cfg.vm.hostname = full
      node_cfg.vm.network 'private_network', ip: ip

      node_cfg.vm.provider 'virtualbox' do |vb|
        vb.name = "k8s-airgap-#{hostname}"
        vb.cpus = 2
        vb.memory = 2048
        vb.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
      end

      # Base bootstrap: devops user, SSH, DNS pointer to OPS — no deployment logic
      node_cfg.vm.provision 'shell', inline: <<-SHELL
        set -euo pipefail
        DOMAIN='#{DOMAIN}'
        HOSTNAME_SHORT='#{hostname}'
        FQDN='#{full}'
        OPS_IP='#{node_ip('ops')}'
        OPS_FQDN='#{fqdn(node_hostname('ops'))}'

        hostnamectl set-hostname "${FQDN}"

        # devops LAB user
        if ! id devops >/dev/null 2>&1; then
          useradd -m -s /bin/bash -G wheel devops
        fi
        echo 'devops:password' | chpasswd
        echo 'devops ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/devops
        chmod 440 /etc/sudoers.d/devops

        # SSH hardening for LAB key auth readiness
        mkdir -p /home/devops/.ssh
        chmod 700 /home/devops/.ssh
        chown -R devops:devops /home/devops/.ssh
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        systemctl reload sshd || systemctl reload ssh || true

        # Point resolvers at OPS DNS. IP comes only from config/network.yml (via Vagrant).
        # All service references elsewhere use DNS/FQDN names.
        mkdir -p /etc/systemd/resolved.conf.d
        cat >/etc/systemd/resolved.conf.d/lab-dns.conf <<EOF
[Resolve]
DNS=${OPS_IP}
Domains=${DOMAIN}
EOF
        systemctl restart systemd-resolved || true

        # Temporary hosts bootstrap until dnsmasq is up (generated later by Ansible)
        if ! grep -q "${OPS_FQDN}" /etc/hosts; then
          echo "${OPS_IP} ${OPS_FQDN} ops zot.${DOMAIN} repo.${DOMAIN} helm.${DOMAIN}" >>/etc/hosts
        fi

        echo "[OK] provisioned base for ${FQDN} (DNS via ${OPS_FQDN})"
      SHELL

      # OPS-only tools for preparation / control plane automation
      if hostname == LAB.fetch('ops_hostname')
        node_cfg.vm.provision 'shell', inline: <<-SHELL
          set -euo pipefail
          dnf install -y python3 python3-pip git curl wget tar unzip jq
          pip3 install --upgrade pip
          pip3 install pyyaml ansible netaddr
          echo "[OK] OPS node tooling installed"
        SHELL
      end
    end
  end
end
