PHONY_TARGETS := $(shell grep -E '^[a-zA-Z0-9_-]+:' Makefile | cut -d: -f1)
.PHONY: $(PHONY_TARGETS)

SHELL := /usr/bin/env bash
ARTEFATOS := artefatos
SNAP := makefile_snapshot
CFG = ./ansible/.ansible.cfg

# Variável para controlar verbosidade (VERBOSE=v, VERBOSE=vv, VERBOSE=vvv)
VERBOSE ?=
ANSIBLE_VERBOSE := $(if $(VERBOSE),-$(VERBOSE),)

.DEFAULT_GOAL := help

help: ## Mostra esta ajuda
	@echo "Lista de targets:"; \
	grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-32s %s\n", $$1, $$2}'

down: ## Interrompe as VMs
	vagrant halt

destroy: ## Destroi as VMs
	vagrant destroy -f

clean: destroy ## Destroi as VMs e remove todos os arquivos gerados automaticamente
	rm -rf $(ARTEFATOS) .vagrant id_ed25519 id_ed25519.pub

arquivos-newlines: ## Adiciona quebra de linha no final dos arquivos que não têm
	find . -type f \
	  -not -path "./.git/*" \
	  -not -path "./artefatos/*" \
	  -exec sh -c '[ -n "$$(tail -c1 "$$1" 2>/dev/null)" ] && echo >> "$$1"' _ {} \;

lint: ## Checagem da estrutura do Ansible
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

k8s-in-a-box: cluster ops exemplos ## Executa todo o projeto

##########################################################################################
################################### Criação do Cluster ###################################

cluster-up: ## Sobe as VMs e recria a pasta artefatos/
	mkdir -p $(ARTEFATOS)
	vagrant up

# Tasks independentes, para executar individualmente (para evitar executar toda a pipeline, ou após um restore de snapshot)
cluster-artefatos: ## Executa apenas a role artefatos
	@echo "Executando role artefatos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-artefatos

cluster-pki: ## Executa apenas a role pki
	@echo "Executando role pki..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-pki

cluster-sistema: ## Executa apenas a role sistema
	@echo "Executando role sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-sistema

cluster-balanceador: ## Executa apenas a role balanceador
	@echo "Executando role balanceador..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-balanceador

cluster-nfs: ## Executa apenas a role balanceador
	@echo "Executando role nfs..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-nfs

cluster-kubernetes-base: ## Executa apenas a role kubernetes-base
	@echo "Executando role kubernetes-base..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kubernetes-base

cluster-etcd: ## Executa apenas a role etcd
	@echo "Executando role etcd..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-etcd

cluster-kube-apiserver: ## Executa apenas a role kube-apiserver
	@echo "Executando role kube-apiserver..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kube-apiserver

cluster-kube-controller-manager: ## Executa apenas a role kube-controller-manager
	@echo "Executando role kube-controller-manager..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kube-controller-manager

cluster-kube-scheduler: ## Executa apenas a role kube-scheduler
	@echo "Executando role kube-controller-manager..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kube-scheduler

cluster-kubelet: ## Executa apenas a role kubelet
	@echo "Executando role kubelet..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kubelet

cluster-kube-proxy: ## Executa apenas a role kube-proxy
	@echo "Executando role kube-proxy..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster-kube-proxy

cluster: cluster-up ## Executa toda a construção do cluster kubernetes
	@echo "Executando todas as roles de cluster..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags cluster

############################################################################################
################################### Operações no Cluster ###################################

ops-up: ## Sobe a vm de ferramentas de operação do cluster
	vagrant up kubox

ops-sistema: ## Executa apenas a role ferramentas-ops
	@echo "Executando role ops-sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-sistema

ops-ferramentas: ## Executa apenas a role ferramentas-ops
	@echo "Executando role ops-ferramentas..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-ferramentas

ops-addons: ## Executa apenas a role configuracoes-ops
	@echo "Executando role ops-addons..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-addons

ops: ops-up ## Executa toda a construção do cliente kubox para operação do cluster
	@echo "Executando todas as roles de operações..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops

################################################################################
################################### Exemplos ###################################

exemplos: ## Executa apenas a role exemplos
	@echo "Executando role exemplos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags exemplos

##############################################################################
################################### Extras ###################################

snapshot: ## Cria uma snapshot única (sempre sobrescreve)
	@if vagrant status | grep -q "not created"; then \
  		echo "Ainda existem VMs não criadas."; \
		exit 1; \
	else  \
		echo "Criando snapshot para todas as VMs..."; \
		vagrant snapshot delete $(SNAP) >/dev/null 2>&1; \
		vagrant snapshot save $(SNAP) >/dev/null 2>&1; \
		echo "Snapshot criada..."; \
	fi

restore: ## Restaura a última snapshot criada
	@if vagrant snapshot list | grep -q $(SNAP); then \
		echo "Restaurando snapshot para todas as VMs..."; \
		vagrant snapshot restore $(SNAP) >/dev/null 2>&1; \
		echo "Snapshot restaurada..."; \
	else \
		echo "Nenhuma snapshot $(SNAP) encontrada."; \
		exit 1; \
	fi
