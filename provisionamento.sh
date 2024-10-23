#!/usr/bin/env bash

# Comando para entrar nas máquinas:
# - ssh -F ssh_config 172.24.0.11
# - ssh -F ssh_config 172.24.0.21
# - ssh -F ssh_config 172.24.0.31
# - ssh -F ssh_config 172.24.0.32

ANSIBLE_CONFIG="./ansible/.ansible.cfg"

ANSIBLE_CONFIG="$ANSIBLE_CONFIG" ansible-playbook "./ansible/playbook.yml"