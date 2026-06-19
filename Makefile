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
	@echo "  make k8s-in-a-box         # Executa a esteira completa (ou 'make build')"
	@echo "  make status               # Mostra o tamanho de cluster ativo"
	@echo ""
	@echo "Lista de targets:"
	@grep -h -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-32s %s\n", $$1, $$2}'
	@echo ""

# ──────────────────────────────────────────────────────────────────────────────
# Configuração & Status
# ──────────────────────────────────────────────────────────────────────────────

init: ## Ativa uma configuração de cluster (ex: CLUSTER=mini)
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

status: ## Mostra a configuração de cluster ativa
	@if [ -L "$(CLUSTER_LINK)" ]; then \
		CURRENT=$$(readlink "$(CLUSTER_LINK)" | sed 's|.*/hosts-||;s/.yml//'); \
		echo "Configuração ativa: $$CURRENT"; \
	elif [ -f "$(CLUSTER_LINK)" ]; then \
		echo "$(CLUSTER_LINK) existe mas não é um symlink"; \
	else \
		echo "Nenhuma configuração ativa (será usado $(CLUSTER))"; \
	fi

check-deps: ## Verifica se todas as dependências locais estão instaladas e configuradas
	@echo "Verificando dependências do host..."
	@FAILED=0; \
	echo -n "  - Ansible: "; \
	if command -v ansible >/dev/null 2>&1; then echo "OK"; else echo "NÃO ENCONTRADO"; FAILED=1; fi; \
	echo -n "  - Vagrant: "; \
	if command -v vagrant >/dev/null 2>&1; then echo "OK"; else echo "NÃO ENCONTRADO"; FAILED=1; fi; \
	echo -n "  - KVM (/dev/kvm): "; \
	if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then echo "OK"; else echo "SEM PERMISSÃO OU NÃO EXISTE"; FAILED=1; fi; \
	echo -n "  - Conexão Libvirt (virsh): "; \
	if virsh uri >/dev/null 2>&1; then echo "OK"; else echo "FALHA"; FAILED=1; fi; \
	echo -n "  - Vagrant Libvirt Plugin: "; \
	if vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt; then echo "OK"; else echo "NÃO ENCONTRADO"; FAILED=1; fi; \
	if [ $$FAILED -ne 0 ]; then \
		echo ""; \
		echo "Erro: Algumas dependências locais estão ausentes ou incorretamente configuradas."; \
		exit 1; \
	else \
		echo "Tudo OK! Pronto para iniciar o provisionamento."; \
	fi

lint: ## Checagem da estrutura do Ansible com ansible-lint
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

arquivos-newlines: ## Adiciona quebra de linha no final dos arquivos que não possuem
	find . -type f \
	  -not -path "./.git/*" \
	  -not -path "./artefatos/*" \
	  -not -path "./.vagrant/*" \
	  -exec sh -c '[ -n "$$(tail -c1 "$$1" 2>/dev/null)" ] && echo >> "$$1"' _ {} \;

# ──────────────────────────────────────────────────────────────────────────────
# Gerenciamento de Máquinas Virtuais (Vagrant)
# ──────────────────────────────────────────────────────────────────────────────

up: garante-config ## Sobe todas as VMs do cluster e cria pasta de artefatos
	mkdir -p $(ARTEFATOS)
	vagrant up

down: garante-config ## Interrompe todas as VMs do cluster (vagrant halt)
	vagrant halt

destroy: garante-config ## Exclui permanentemente todas as VMs (vagrant destroy)
	vagrant destroy -f

clean: destroy ## Deleta as VMs e limpa todos os artefatos, chaves e symlinks temporários
	rm -rf $(ARTEFATOS) .vagrant .cache id_ed25519 id_ed25519.pub inventario/hosts.yml

# ──────────────────────────────────────────────────────────────────────────────
# Provisionamento do Kubernetes (Cluster)
# ──────────────────────────────────────────────────────────────────────────────

infra: garante-config ## Prepara infraestrutura pré-k8s (PKI, SO base, Balanceador, NFS)
	@echo "Executando preparação da infraestrutura pré-Kubernetes..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-artefatos,cluster-pki,cluster-sistema,cluster-balanceador,cluster-nfs

control-plane: garante-config ## Instala o Kubernetes core (Kubelet, Etcd, Static Pods)
	@echo "Instalando componentes do Kubernetes core..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster-kubernetes-base,cluster-kubelet,cluster-etcd,cluster-kube-apiserver,cluster-kube-controller-manager,cluster-kube-scheduler

cluster: garante-config ## Executa o provisionamento do cluster completo (infra + control-plane)
	@echo "Provisionando cluster Kubernetes completo..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "$(PLAYBOOK)" $(ANSIBLE_VERBOSE) --tags cluster

# ──────────────────────────────────────────────────────────────────────────────
# Operações & Rede (Máquina Cliente kubox)
# ──────────────────────────────────────────────────────────────────────────────

ops-up: garante-config
	vagrant up kubox

ops-setup: ops-up ## Prepara a VM kubox com ferramentas de operação (kubectl, helm, cli)
	@echo "Configurando ferramentas operacionais na VM kubox..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-sistema,ops-ferramentas

cni: ops-up ## Instala e configura a pilha de rede/gateway CNI ativa (Cilium ou Canal)
	@echo "Instalando CNI e componentes de rede..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops-cni

ops: ops-up ## Provisiona completamente a VM de operações (ops-setup + cni)
	@echo "Executando provisionamento completo da VM de operações..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags ops

# ──────────────────────────────────────────────────────────────────────────────
# Aplicações & Exemplos
# ──────────────────────────────────────────────────────────────────────────────

addons: garante-config ## Instala ferramentas operacionais adicionais (Prometheus, Grafana, VPA, Headlamp)
	@echo "Instalando addons operacionais no cluster..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/addons.yml" $(ANSIBLE_VERBOSE) --tags addons

exemplos: garante-config ## Faz deploy das aplicações de demonstração (Hello App, Contador)
	@echo "Instalando aplicações de exemplos..."
	ANSIBLE_CONFIG="$(CFG)" ansible-playbook "./ansible/ops.yml" $(ANSIBLE_VERBOSE) --tags exemplos

# ──────────────────────────────────────────────────────────────────────────────
# Pipelines Principais & Extras
# ──────────────────────────────────────────────────────────────────────────────

build: up cluster ops addons exemplos ## Executa todo o provisionamento do zero (esteira completa)

k8s-in-a-box: build ## Atalho para executar todo o provisionamento (make build)
	@echo "Cluster k8s-in-a-box provisionado com sucesso!"
	@(xdg-open http://172.24.0.110 || open http://172.24.0.110 || echo "Acesse http://172.24.0.110 no seu navegador.") 2>/dev/null

snapshot: ## Cria uma snapshot única de todas as VMs
	@if vagrant status | grep -q "not created"; then \
  		echo "Ainda existem VMs não criadas."; \
		exit 1; \
	else  \
		echo "Criando snapshot para todas as VMs..."; \
		vagrant snapshot delete $(SNAP) >/dev/null 2>&1; \
		vagrant snapshot save $(SNAP) >/dev/null 2>&1; \
		echo "Snapshot criada..."; \
	fi

restore: ## Restaura o cluster para a última snapshot criada
	@if vagrant snapshot list | grep -q $(SNAP); then \
		echo "Restaurando snapshot para todas as VMs..."; \
		vagrant snapshot restore $(SNAP) >/dev/null 2>&1; \
		echo "Snapshot restaurada..."; \
	else \
		echo "Nenhuma snapshot $(SNAP) encontrada."; \
		exit 1; \
	fi
