#!/usr/bin/env bash

# Comando para entrar nas máquinas:
# - ssh -F ssh_config 172.24.0.11
# - ssh -F ssh_config 172.24.0.21
# - ssh -F ssh_config 172.24.0.31
# - ssh -F ssh_config 172.24.0.32

set -euo pipefail

function main() {
    local vms=$(vagrant status | grep running | awk '{print $1}')

    CFG="./ansible/.ansible.cfg"
    mkdir artefatos
    chmod 0600 id_ed25519

    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" --tags todas

    ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --tags artefatos

    ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --tags pki

    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags sistema
    #criar_snapshot 01_sistema_pronto

    #restaurar_snapshot 01_sistema_pronto

    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags haproxy
    #criar_snapshot 02_haproxy_pronto

    #restaurar_snapshot 02_haproxy_pronto
    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags etcd
    #criar_snapshot 03_etcd_pronto

    #restaurar_snapshot 03_etcd_pronto
    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags k8s_base
    #criar_snapshot 04_k8s_base_pronto

    #restaurar_snapshot 04_k8s_base_pronto
    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags kube_apiserver
    #criar_snapshot 05_kube_apiserver_pronto

    #restaurar_snapshot 05_kube_apiserver_pronto
    #ANSIBLE_CONFIG="$CFG" ansible-playbook "./ansible/playbook.yml" -v --limit "$vms" --tags kube_controller_manager
    #criar_snapshot 06_kube_controller_manager_pronto
}

function criar_snapshot() {
    local base_dir="k8sbox"
    local nome_snapshot="$1"
    local snapshot_desc="${2:-}"
    local vms=$(vagrant status | grep running | awk '{print $1}')
    
    vagrant halt $vms
    
    for vm in $vms; do
        echo "Criando snapshot para $vm..."
        local nome_vm="${base_dir}_${vm}"
        
        if virsh --connect qemu:///system snapshot-list "$nome_vm" | grep -q "$nome_snapshot"; then
            echo "Deletando snapshot existente $nome_snapshot para $nome_vm..."
            virsh --connect qemu:///system snapshot-delete "$nome_vm" "$nome_snapshot" >/dev/null
        else
            echo "Nenhum snapshot $nome_snapshot encontrado para $nome_vm..."
        fi
        
        virsh --connect qemu:///system snapshot-create-as \
            "$nome_vm" \
            "$nome_snapshot" \
            --description "${snapshot_desc:-Snapshot criado pelo script de provisionamento em $(date '+%Y-%m-%d %H:%M:%S')}" \
            --atomic >/dev/null
        
        echo "Snapshot $nome_snapshot criado para $nome_vm..."
    done
    
    vagrant up $vms 2>&1 | grep -E "Bringing|Error:"
}

function restaurar_snapshot() {
    local base_dir="k8sbox"
    local nome_snapshot=$1
    local vms=$(vagrant status | grep running | awk '{print $1}')
    
    vagrant halt  $vms
    
    for vm in $vms; do
        echo "Restaurando snapshot para $vm..."
        local nome_vm="${base_dir}_${vm}"

        if virsh -c qemu:///system snapshot-list "$nome_vm" | grep -q "$nome_snapshot"; then
            virsh -c qemu:///system snapshot-revert "$nome_vm" "$nome_snapshot" >/dev/null
        fi
    done
    
    vagrant up $vms 2>&1 | grep -E "Bringing|Error:"
}

time main