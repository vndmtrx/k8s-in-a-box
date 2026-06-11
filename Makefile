PHONY_TARGETS := $(shell grep -E '^[a-zA-Z0-9_-]+:' Makefile | cut -d: -f1)
.PHONY: $(PHONY_TARGETS)

SHELL := /usr/bin/env bash
ARTEFATOS := artefatos
SNAP := makefile_snapshot
CFG = ./ansible/.ansible.cfg

-include config.mk

# Variáveis para controlar o tipo dos clusters
# Opções de CLUSTER: (nano, mini, completo)
CLUSTER ?= mini

CLUSTER_SOURCE := configs/hosts-$(CLUSTER).yml
CLUSTER_LINK := inventario/hosts.yml
PLAYBOOK := ./ansible/cluster.yml

# Variável para controlar verbosidade (VERBOSE=v, VERBOSE=vv, VERBOSE=vvv)
VERBOSE ?=
ANSIBLE_VERBOSE := $(if $(VERBOSE),-$(VERBOSE),)

.DEFAULT_GOAL := help

help: ## Mostra esta ajuda
	@echo "════════════════════════════════════════════════════════════"
	@echo "  K8s in a Box - Makefile"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Uso:"
	@echo "  make init                 # Ativa a configuração definida no config.mk (disponíveis: completo, mini, nano)"
	@echo "  make k8s-in-a-box         # Usa alvo ativo (ou padrão: mini)"
	@echo "  make status               # Mostra alvo ativo"
	@echo ""
	@echo "Lista de targets:"
	@grep -h -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-32s %s\n", $$1, $$2}'
	@echo ""

check-deps: ## Verifica se todas as dependências locais estão instaladas e configuradas
	@echo "Verificando dependências do host..."
	@FAILED=0; \
	echo -n "  - Ansible: "; \
	if command -v ansible >/dev/null 2>&1; then echo "OK"; else echo "NÃO ENCONTRADO"; FAILED=1; fi; \
	echo -n "  - Vagrant: "; \
	if command -v vagrant >/dev/null 2>&1; then echo "OK"; else echo "NÃO ENCONTRADO"; FAILED=1; fi; \
	echo -n "  - KVM (/dev/kvm): "; \
	if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then echo "OK"; else echo "SEM PERMISSÃO OU NÃO EXISTE (adicione seu usuário ao grupo kvm)"; FAILED=1; fi; \
	echo -n "  - Conexão Libvirt (virsh): "; \
	if virsh uri >/dev/null 2>&1; then echo "OK"; else echo "FALHA (verifique se o serviço libvirtd está rodando e se seu usuário está no grupo libvirt)"; FAILED=1; fi; \
	echo -n "  - Vagrant Libvirt Plugin: "; \
	if vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt; then echo "OK"; else echo "NÃO ENCONTRADO (execute: vagrant plugin install vagrant-libvirt)"; FAILED=1; fi; \
	if [ $$FAILED -ne 0 ]; then \
		echo ""; \
		echo "Erro: Algumas dependências locais estão ausentes ou incorretamente configuradas."; \
		exit 1; \
	else \
		echo "Tudo OK! Pronto para iniciar o provisionamento."; \
	fi

init: ## Ativa uma configuração de cluster
	@if [ ! -f "$(CLUSTER_SOURCE)" ]; then \
		echo "Erro: $(CLUSTER_SOURCE) não encontrado."; \
		echo "Configurações disponíveis:"; \
		ls -1 configs/hosts-*.yml 2>/dev/null | sed 's|configs/hosts-||;s/.yml$$//' | sed 's/^/  - /'; \
		exit 1; \
	fi
	@mkdir -p inventario
	@rm -f "$(CLUSTER_LINK)"
	@ln -sf ../$(CLUSTER_SOURCE) "$(CLUSTER_LINK)"
	@echo "Configuração $(CLUSTER) ativada"

garante-config: ## Garante que a configuração ativa está sincronizada com o config.mk
	@CURRENT_LINK=$$(readlink "$(CLUSTER_LINK)" 2>/dev/null || echo ""); \
	EXPECTED_LINK="../$(CLUSTER_SOURCE)"; \
	if [ "$$CURRENT_LINK" != "$$EXPECTED_LINK" ]; then \
		echo "Sincronizando configuração do inventário para $(CLUSTER)..."; \
		$(MAKE) init; \
	fi

status: ## Mostra a configuração ativa
	@if [ -L "$(CLUSTER_LINK)" ]; then \
		CURRENT=$$(readlink "$(CLUSTER_LINK)" | sed 's|.*/hosts-||;s/.yml//'); \
		echo "Configuração ativa: $$CURRENT"; \
	elif [ -f "$(CLUSTER_LINK)" ]; then \
		echo "$(CLUSTER_LINK) existe mas não é um symlink"; \
	else \
		echo "Nenhuma configuração ativa (será usado $(CLUSTER))"; \
	fi

down: garante-config ## Interrompe as VMs
	vagrant halt

destroy: garante-config ## Destroi as VMs
	vagrant destroy -f

clean: destroy ## Destroi as VMs e remove todos os arquivos gerados automaticamente
	rm -rf $(ARTEFATOS) .vagrant id_ed25519 id_ed25519.pub inventario/hosts.yml

arquivos-newlines: ## Adiciona quebra de linha no final dos arquivos que não têm
	find . -type f \
	  -not -path "./.git/*" \
	  -not -path "./artefatos/*" \
	  -exec sh -c '[ -n "$$(tail -c1 "$$1" 2>/dev/null)" ] && echo >> "$$1"' _ {} \;

lint: ## Checagem da estrutura do Ansible
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

k8s-in-a-box: cluster ops addons exemplos ## Executa todo o projeto
	@echo "Cluster k8s-in-a-box provisionado com sucesso!"
	@(xdg-open http://172.24.0.110 || open http://172.24.0.110 || echo "Acesse http://172.24.0.110 no seu navegador.") 2>/dev/null

##########################################################################################
################################### Criação do Cluster ###################################

cluster-up: garante-config ## Sobe as VMs e recria a pasta artefatos/
	mkdir -p $(ARTEFATOS)
	vagrant up

# Tasks independentes, para executar individualmente (para evitar executar toda a pipeline, ou após um restore de snapshot)
cluster-artefatos: garante-config ## Executa apenas a role artefatos
	@echo "Executando role artefatos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-artefatos

cluster-pki: garante-config ## Executa apenas a role pki
	@echo "Executando role pki..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-pki

cluster-sistema: garante-config ## Executa apenas a role sistema
	@echo "Executando role sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-sistema

cluster-balanceador: garante-config ## Executa apenas a role balanceador
	@echo "Executando role balanceador..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-balanceador

cluster-nfs: garante-config ## Executa apenas a role nfs
	@echo "Executando role nfs..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-nfs

cluster-kubernetes-base: garante-config ## Executa apenas a role kubernetes-base
	@echo "Executando role kubernetes-base..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kubernetes-base

cluster-etcd: garante-config ## Executa apenas a role etcd
	@echo "Executando role etcd..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-etcd

cluster-kube-apiserver: garante-config ## Executa apenas a role kube-apiserver
	@echo "Executando role kube-apiserver..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kube-apiserver

cluster-kube-controller-manager: garante-config ## Executa apenas a role kube-controller-manager
	@echo "Executando role kube-controller-manager..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kube-controller-manager

cluster-kube-scheduler: garante-config ## Executa apenas a role kube-scheduler
	@echo "Executando role kube-scheduler..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kube-scheduler

cluster-kubelet: garante-config ## Executa apenas a role kubelet
	@echo "Executando role kubelet..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kubelet

cluster: cluster-up ## Executa toda a construção do cluster kubernetes
	@echo "Executando todas as roles de cluster..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster

############################################################################################
################################### Operações no Cluster ###################################

ops-up: garante-config ## Sobe a vm de ferramentas de operação do cluster
	vagrant up kubox

ops-sistema: garante-config ## Executa apenas a role ferramentas-ops
	@echo "Executando role ops-sistema..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-sistema

ops-ferramentas: garante-config ## Executa apenas a role ferramentas-ops
	@echo "Executando role ops-ferramentas..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-ferramentas

ops-cni: garante-config ## Executa apenas a role de CNI e dependências de rede
	@echo "Executando role ops-cni..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-cni

ops-kube-proxy: garante-config ## Executa apenas a role kube-proxy (se Canal CNI)
	@echo "Executando role ops-kube-proxy..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-kube-proxy

ops-kubevip: garante-config ## Executa apenas a role kube-vip (se Canal CNI)
	@echo "Executando role ops-kubevip..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-kubevip

ops-traefik: garante-config ## Executa apenas a role traefik (se Canal CNI)
	@echo "Executando role ops-traefik..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-traefik

ops: ops-up ## Executa toda a construção do cliente kubox para operação do cluster
	@echo "Executando todas as roles de operações..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops

addons-up: garante-config ## Sobe a vm se necessário (usa kubox)
	vagrant up kubox

addons: addons-up ## Executa o playbook de addons independentes
	@echo "Executando todos os addons independentes..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/addons.yml" $(ANSIBLE_VERBOSE) --tags addons

ops-addons: addons ## Atalho para rodar addons independentes

################################################################################
################################### Exemplos ###################################

exemplos: garante-config ## Executa apenas a role exemplos
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
