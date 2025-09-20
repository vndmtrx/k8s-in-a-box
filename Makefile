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
	awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-18s %s\n", $$1, $$2}'

up: ## Sobe as VMs e recria a pasta artefatos/
	mkdir -p $(ARTEFATOS)
	vagrant up

down: ## Interrompe as VMs
	vagrant halt

destroy: ## Destroi as VMs
	vagrant destroy -f

clean: destroy ## Destroi as VMs e remove todos os arquivos gerados automaticamente
	rm -rf $(ARTEFATOS) .vagrant id_ed25519 id_ed25519.pub

lint: # Checagem da estrutura do Ansible
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

# Tasks com encadeamento de execução

artefatos: up apenas_artefatos ## Executa todas as dependências para a role artefatos

pki: artefatos apenas_pki ## Executa todas as dependências para a role pki

sistema: pki apenas_sistema ## Executa todas as dependências para a role pki

haproxy: sistema apenas_haproxy ## Executa todas as dependências para a role haproxy

etcd: haproxy apenas_etcd ## Executa todas as dependências para a role etcd

k8sbase: etcd apenas_k8sbase ## Executa todas as dependências para a role k8sbase

# Tasks independentes, para executar individualmente (para evitar executar toda a pipeline, ou após um restore de snapshot)

apenas_artefatos: ## Executa apenas a role artefatos (use com um snapshot da máquina não provisionada)
	@echo "Executando role artefatos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags artefatos

apenas_pki: ## Executa apenas a role pki (use com um snapshot de artefatos)
	@echo "Executando role pki..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags pki

apenas_sistema: ## Executa apenas a role sistema (use com um snapshot de pki)
	@echo "Executando role sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags sistema

apenas_haproxy: ## Executa apenas a role haproxy (use com um snapshot de sistema)
	@echo "Executando role haproxy..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags haproxy

apenas_etcd: ## Executa apenas a role etcd (use com um snapshot de haproxy)
	@echo "Executando role etcd..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags etcd

apenas_k8sbase: ## Executa apenas a role k8sbase (use com um snapshot de haproxy)
	@echo "Executando role k8sbase..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/playbook.yml" $(ANSIBLE_VERBOSE) --tags k8s-base

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