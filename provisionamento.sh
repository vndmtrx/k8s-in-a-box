#!/usr/bin/env bash

# Comando para entrar nas máquinas:
# - ssh -F ssh_config 172.24.0.11
# - ssh -F ssh_config 172.24.0.21
# - ssh -F ssh_config 172.24.0.31
# - ssh -F ssh_config 172.24.0.32

ANSIBLE_CONFIG="./ansible/.ansible.cfg"

chmod 0600 id_ed25519
ANSIBLE_CONFIG="$ANSIBLE_CONFIG" ansible-playbook -v "./ansible/playbook.yml"

#ANSIBLE_CONFIG="$ANSIBLE_CONFIG" ansible-playbook "./ansible/playbook.yml" --tags "pki:monitor"

#cat arquivos/pki/status-certificados.txt