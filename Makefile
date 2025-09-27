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
	awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-22s %s\n", $$1, $$2}'

up: ## Sobe as VMs e recria a pasta artefatos/
	mkdir -p $(ARTEFATOS)
	vagrant up

down: ## Interrompe as VMs
	vagrant halt

destroy: ## Destroi as VMs
	vagrant destroy -f

clean: destroy ## Destroi as VMs e remove todos os arquivos gerados automaticamente
	rm -rf $(ARTEFATOS) .vagrant id_ed25519 id_ed25519.pub

lint: ## Checagem da estrutura do Ansible
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

# Tasks independentes, para executar individualmente (para evitar executar toda a pipeline, ou após um restore de snapshot)
artefatos: ## Executa apenas a role artefatos (use com um snapshot da máquina não provisionada)
	@echo "Executando role artefatos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags artefatos

pki: ## Executa apenas a role pki (use com um snapshot de artefatos)
	@echo "Executando role pki..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags pki

sistema: ## Executa apenas a role sistema (use com um snapshot de pki)
	@echo "Executando role sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags sistema

haproxy: ## Executa apenas a role haproxy (use com um snapshot de sistema)
	@echo "Executando role haproxy..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags haproxy

kubernetes-base: ## Executa apenas a role kubernetes-base (use com um snapshot de haproxy)
	@echo "Executando role kubernetes-base..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags kubernetes-base

etcd: ## Executa apenas a role etcd (use com um snapshot de kubernetes-base)
	@echo "Executando role etcd..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags etcd

kube-apiserver: ## Executa apenas a role kube-apiserver (use com um snapshot de etcd)
	@echo "Executando role kube-apiserver..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags kube-apiserver

kube-controller-manager: ## Executa apenas a role kube-controller-manager (use com um snapshot de kube-apiserver)
	@echo "Executando role kube-controller-manager..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags kube-controller-manager

kube-scheduler: ## Executa apenas a role kube-scheduler (use com um snapshot de kube-controller-manager)
	@echo "Executando role kube-controller-manager..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags kube-scheduler

kubelet: ## Executa apenas a role kubelet (use com um snapshot de kube-scheduler)
	@echo "Executando role kubelet..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags kubelet

k8s-in-a-box: up ## Executa todo o projeto
	@echo "Executando todas as roles..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/cluster.yml" $(ANSIBLE_VERBOSE) --tags todas

# Tasks com encadeamento de execução
cadeia-artefatos: up artefatos ## Executa todas as dependências para a role artefatos

cadeia-pki: cadeia-artefatos pki ## Executa todas as dependências para a role pki

cadeia-sistema: cadeia-pki sistema ## Executa todas as dependências para a role pki

cadeia-haproxy: cadeia-sistema haproxy ## Executa todas as dependências para a role haproxy

cadeia-kubernetes-base: cadeia-haproxy kubernetes-base ## Executa todas as dependências para a role kubernetes-base

cadeia-etcd: cadeia-kubernetes-base etcd ## Executa todas as dependências para a role etcd

cadeia-kube-apiserver: cadeia-etcd kube-apiserver ## Executa todas as dependências para a role kube-apiserver

cadeia-kube-controller-manager: cadeia-kube-apiserver kube-controller-manager ## Executa todas as dependências para a role kube-controller-manager

cadeia-kube-scheduler: cadeia-kube-controller-manager kube-scheduler ## Executa todas as dependências para a role kube-scheduler

cadeia-kubelet: cadeia-kube-scheduler kubelet ## Executa todas as dependências para a role kubelet

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