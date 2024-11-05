#!/usr/bin/env bash

# Comando para entrar nas máquinas:
# - ssh -F ssh_config 172.24.0.11
# - ssh -F ssh_config 172.24.0.21
# - ssh -F ssh_config 172.24.0.31
# - ssh -F ssh_config 172.24.0.32

set -euo pipefail

CFG="./ansible/.ansible.cfg"

chmod 0600 id_ed25519
ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags todas

#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags sistema
#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --tags pki
#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags haproxy
#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags etcd
#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags kube_apiserver

#ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags "pki:monitor"
#cat arquivos/pki/status-certificados.txt