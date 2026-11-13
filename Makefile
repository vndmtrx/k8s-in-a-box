PHONY_TARGETS := $(shell grep -E '^[a-zA-Z0-9_-]+:' Makefile | cut -d: -f1)
.PHONY: $(PHONY_TARGETS)

SHELL := /usr/bin/env bash
# Pasta de tudo o que o projeto gera (cache, VMs, chaves, PKI, logs). Não é
# configurável de propósito: os alvos clean-* e purge apagam partes dela.
override TARGET := .target
SNAP := makefile_snapshot
CFG = ./ansible/.ansible.cfg

-include config.mk

# Variáveis para controlar o tipo dos clusters
# Opções de CLUSTER: (mini, completo)
CLUSTER ?= mini

CLUSTER_SOURCE := configs/hosts-$(CLUSTER).yml
CLUSTER_LINK := inventario/hosts.yml
PLAYBOOK := ./ansible/cluster.yml
PROVISIONA = ANSIBLE_CONFIG="$(CFG)" ansible-playbook ./ansible/provisiona.yml $(ANSIBLE_VERBOSE)

# Pré-requisitos do host (usados pelo alvo bootstrap)
# URI do libvirt (sempre qemu:///system, sem sudo)
LIBVIRT_URI ?= qemu:///system
# Prefixo dos domínios no libvirt (igual a libvirt_prefixo em inventario/group_vars/all.yml)
VM_PREFIXO ?= k8sbox
# Tamanho de disco padrão por VM quando o host não define disk_size no inventário
DISK_SIZE_DEFAULT ?= 20G

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
	@echo "  make init                 # Ativa a configuração definida no config.mk (disponíveis: completo, mini)"
	@echo "  make k8s-in-a-box         # Executa a esteira completa e grava logs em $(TARGET)/logs/ ('make build' faz o mesmo sem logs)"
	@echo "  make ssh-<host>           # Abre SSH numa VM (ex.: make ssh-manager1)"
	@echo "  make status               # Mostra o tamanho de cluster ativo"
	@echo ""
	@echo "Lista de targets:"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?##' $(MAKEFILE_LIST) | \
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
	@mkdir -p "$(TARGET)/ansible"
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

bootstrap: ## Valida pré-requisitos do host (binários, collection, permissões, .target e recursos) antes de provisionar
	@echo "Validando pré-requisitos do host para o provisionamento libvirt/Ansible..."
	@set -euo pipefail; \
	falha() { echo ""; echo "Erro: pré-requisito ausente -> $$1"; exit 1; }; \
	\
	for bin in virsh qemu-img ssh-keygen ansible; do \
		echo -n "  - Binário $$bin: "; \
		if command -v $$bin >/dev/null 2>&1; then echo "OK"; else echo "NÃO ENCONTRADO"; falha "o binário '$$bin' não está instalado"; fi; \
	done; \
	echo -n "  - Binário cloud-localds/genisoimage: "; \
	if command -v cloud-localds >/dev/null 2>&1; then echo "OK (cloud-localds)"; \
	elif command -v genisoimage >/dev/null 2>&1; then echo "OK (genisoimage)"; \
	else echo "NÃO ENCONTRADO"; falha "nem 'cloud-localds' (pacote cloud-image-utils) nem 'genisoimage' (pacote genisoimage) foram encontrados"; fi; \
	\
	echo -n "  - Collection community.libvirt: "; \
	if ansible-galaxy collection list 2>/dev/null | grep -q '^community\.libvirt '; then echo "OK"; \
	else echo "NÃO ENCONTRADA"; falha "a collection Ansible 'community.libvirt' não está instalada (ansible-galaxy collection install community.libvirt)"; fi; \
	\
	echo -n "  - Inventário efetivo: "; \
	INV="$(CLUSTER_LINK)"; \
	if [ ! -e "$$INV" ]; then INV="$(CLUSTER_SOURCE)"; fi; \
	if [ ! -e "$$INV" ]; then echo "NÃO ENCONTRADO"; falha "nenhum inventário efetivo encontrado ('$(CLUSTER_LINK)' ou '$(CLUSTER_SOURCE)'); rode 'make init'"; fi; \
	echo "$$INV"; \
	INVJSON=$$(ansible-inventory -i "$$INV" --list 2>/dev/null) || falha "não foi possível interpretar o inventário efetivo ('$$INV')"; \
	\
	LIBVIRT_PY=$$(echo "$$INVJSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); h=next(iter(d["_meta"]["hostvars"].values())); print(h.get("libvirt_python","/usr/bin/python3"))'); \
	echo -n "  - Módulo Python libvirt ($$LIBVIRT_PY): "; \
	if "$$LIBVIRT_PY" -c 'import libvirt' >/dev/null 2>&1; then echo "OK"; \
	else echo "AUSENTE"; falha "'$$LIBVIRT_PY -c \"import libvirt\"' falhou (Debian: sudo apt install python3-libvirt; AlmaLinux/Fedora: sudo dnf install python3-libvirt)"; fi; \
	\
	echo -n "  - Grupo libvirt: "; \
	if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx libvirt; then echo "OK"; \
	else echo "FORA DO GRUPO"; falha "o usuário '$$(id -un)' não pertence ao grupo 'libvirt' (sudo usermod -aG libvirt $$(id -un) e reiniciar a sessão)"; fi; \
	\
	echo -n "  - Conexão $(LIBVIRT_URI) sem sudo: "; \
	if virsh -c "$(LIBVIRT_URI)" list >/dev/null 2>&1; then echo "OK"; \
	else echo "FALHA"; falha "'virsh -c $(LIBVIRT_URI) list' não respondeu sem sudo (verifique o grupo libvirt e o serviço libvirtd)"; fi; \
	\
	echo -n "  - KVM (/dev/kvm): "; \
	if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then echo "OK"; \
	else echo "SEM PERMISSÃO OU NÃO EXISTE"; falha "/dev/kvm não existe ou não tem leitura/escrita (verifique virtualização habilitada e o grupo kvm)"; fi; \
	\
	echo -n "  - Pasta $(TARGET) gravável: "; \
	mkdir -p "$(TARGET)/ansible" 2>/dev/null && touch "$(TARGET)/.bootstrap_teste" 2>/dev/null && rm -f "$(TARGET)/.bootstrap_teste" || { echo "NÃO GRAVÁVEL"; falha "não consegui gravar em '$(CURDIR)/$(TARGET)'"; }; \
	echo "OK"; \
	\
	echo -n "  - Usuário do QEMU atravessa o caminho até $(TARGET): "; \
	if ACESSO=$$(python3 -B scripts/bootstrap_acesso_qemu.py "$(CURDIR)/$(TARGET)" "$(LIBVIRT_URI)" 2>&1); then echo "OK"; [ -z "$$ACESSO" ] || echo "$$ACESSO" | sed 's/^/      /'; \
	else echo "SEM ACESSO"; echo "$$ACESSO" | sed 's/^/      /'; falha "o usuário do QEMU precisa de 'x' nos diretórios acima (rode os comandos setfacl indicados)"; fi; \
	\
	echo "  - Calculando recursos exigidos pela topologia..."; \
	EXISTENTES=$$(virsh -c "$(LIBVIRT_URI)" list --name 2>/dev/null | sed -n 's/^$(VM_PREFIXO)-//p' | tr '\n' ' '); \
	RES=$$(echo "$$INVJSON" | DISK_SIZE_DEFAULT="$(DISK_SIZE_DEFAULT)" HOSTS_EXISTENTES="$$EXISTENTES" python3 -B "scripts/bootstrap_recursos.py") || falha "não foi possível calcular os recursos da topologia"; \
	REQ_MEM_MB=$$(echo "$$RES" | awk '{print $$1}'); \
	REQ_DISK_GB=$$(echo "$$RES" | awk '{print $$2}'); \
	NUM_HOSTS=$$(echo "$$RES" | awk '{print $$3}'); \
	echo "    topologia '$(CLUSTER)': $$NUM_HOSTS VMs a criar ou ligar, RAM exigida $$REQ_MEM_MB MiB, disco exigido $$REQ_DISK_GB GiB (VMs já ligadas não contam)"; \
	\
	echo -n "  - RAM livre suficiente: "; \
	AVAIL_MEM_MB=$$(awk '/^MemAvailable:/{printf "%d", $$2/1024}' /proc/meminfo); \
	if [ "$${AVAIL_MEM_MB:-0}" -ge "$$REQ_MEM_MB" ]; then echo "OK ($$AVAIL_MEM_MB MiB disponíveis)"; \
	else echo "INSUFICIENTE"; falha "RAM livre insuficiente: $$AVAIL_MEM_MB MiB disponíveis, $$REQ_MEM_MB MiB exigidos pela topologia '$(CLUSTER)'"; fi; \
	\
	echo -n "  - Disco livre suficiente: "; \
	AVAIL_DISK_MB=$$(df -Pm "$(TARGET)" 2>/dev/null | awk 'NR==2{print $$4}'); \
	AVAIL_DISK_GB=$$(( $${AVAIL_DISK_MB:-0} / 1024 )); \
	if [ "$$AVAIL_DISK_GB" -ge "$$REQ_DISK_GB" ]; then echo "OK ($$AVAIL_DISK_GB GiB disponíveis em $(CURDIR)/$(TARGET))"; \
	else echo "INSUFICIENTE"; falha "disco livre insuficiente em '$(CURDIR)/$(TARGET)': $$AVAIL_DISK_GB GiB disponíveis, $$REQ_DISK_GB GiB exigidos pela topologia '$(CLUSTER)'"; fi; \
	\
	echo ""; \
	echo "Tudo OK! Pré-requisitos do host validados. Pronto para iniciar o provisionamento."

lint: ## Checagem da estrutura do Ansible com ansible-lint
	@command -v ansible-lint >/dev/null 2>&1 || { echo "ansible-lint não está instalado."; exit 1; }
	@ansible-lint -q ansible/ || true

arquivos-newlines: ## Adiciona quebra de linha no final dos arquivos que não possuem
	find . -type f \
	  -not -path "./.git/*" \
	  -not -path "./.target/*" \
	  -not -path "./.vagrant/*" \
	  -exec sh -c '[ -n "$$(tail -c1 "$$1" 2>/dev/null)" ] && echo >> "$$1"' _ {} \;

# ──────────────────────────────────────────────────────────────────────────────
# Gerenciamento de Máquinas Virtuais (Vagrant)
# ──────────────────────────────────────────────────────────────────────────────

up: garante-config bootstrap ## Cria e liga as VMs do cluster (menos as com sobe_com_cluster: false, como o kubox)
	$(PROVISIONA) --tags criar -e apenas_sobe_com_cluster=true

down: garante-config ## Desliga todas as VMs do cluster, sem removê-las
	$(PROVISIONA) --tags desligar

ssh-%: garante-config
	@dest=$$(ansible-inventory -i inventario/ --host "$*" 2>/dev/null | python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); print("%s@%s" % (d["ansible_user"], d["ansible_host"]) if d.get("ansible_host") else "")'); \
	if [ -z "$$dest" ]; then echo "Host '$*' não existe no inventário ativo ($(CLUSTER)). Hosts:"; ansible-inventory -i inventario/ --list | python3 -c 'import json,sys; print("  " + "\n  ".join(sorted(json.load(sys.stdin)["_meta"]["hostvars"])))'; exit 1; fi; \
	exec ssh -F ssh_config "$$dest"

# ──────────────────────────────────────────────────────────────────────────────
# Limpeza em camadas. Cada alvo apaga também o que os anteriores apagam
# (exceto que clean-vms e acima removem as VMs em vez de só restaurá-las).
#
#   clean-k8s      o Kubernetes: as VMs voltam ao snapshot 'so' (SO pronto)
#   clean-vms      VMs e $(TARGET)/vms
#   clean-cluster  + $(TARGET)/cluster (chave SSH, PKI), $(TARGET)/ansible e a rede
#   clean-all      + $(TARGET)/cache (imagens, binários, imagens OCI)
#   purge          + $(TARGET)/logs, ou seja, o $(TARGET) inteiro
# ──────────────────────────────────────────────────────────────────────────────

clean-k8s: garante-config ## Volta as VMs ao snapshot 'so': apaga o Kubernetes e mantém o SO pronto
	$(PROVISIONA) --tags restaurar-so

clean-vms: garante-config ## Remove as VMs e .target/vms (mantém chave SSH, PKI e cache)
	$(PROVISIONA) --tags remover
	rm -rf "$(TARGET)/vms"

clean-cluster: clean-vms ## clean-vms + remove a rede, a chave SSH, a PKI e o estado do Ansible
	$(PROVISIONA) --tags remover-rede
	rm -rf "$(TARGET)/cluster" "$(TARGET)/ansible"
	rm -f "$(CLUSTER_LINK)"

clean-all: clean-cluster ## clean-cluster + apaga o cache (imagens base, binários e imagens OCI); mantém os logs
	rm -rf "$(TARGET)/cache"

purge: clean-all ## clean-all + apaga os logs: remove o .target inteiro e permite recomeçar do zero
	rm -rf "$(TARGET)"

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

ops-up: garante-config ## Cria e liga só a VM kubox (cliente de operações)
	$(PROVISIONA) --tags criar --limit kubox

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

build: up cluster ops addons exemplos ## Executa todo o provisionamento do zero, sem gravar logs (para logs, use k8s-in-a-box)

k8s-in-a-box: garante-config ## Executa a esteira completa e grava logs e métricas em .target/logs/AAAAMMDDhhmmss/
	@CLUSTER="$(CLUSTER)" python3 -B scripts/execucao.py up cluster ops addons exemplos
	@echo "Cluster k8s-in-a-box provisionado com sucesso!"
	@(xdg-open http://172.24.0.110 || open http://172.24.0.110 || echo "Acesse http://172.24.0.110 no seu navegador.") 2>/dev/null

snapshot: ## Cria um snapshot único (nome makefile_snapshot) de todas as VMs do projeto
	@vms=$$(virsh -c "$(LIBVIRT_URI)" list --all --name | grep '^$(VM_PREFIXO)-' || true); \
	if [ -z "$$vms" ]; then \
		echo "Ainda não existem VMs. Rode 'make up' antes."; \
		exit 1; \
	fi; \
	echo "Criando snapshot para todas as VMs..."; \
	for vm in $$vms; do \
		virsh -c "$(LIBVIRT_URI)" snapshot-delete "$$vm" "$(SNAP)" >/dev/null 2>&1 || true; \
		virsh -c "$(LIBVIRT_URI)" snapshot-create-as "$$vm" "$(SNAP)" >/dev/null || { echo "Falha ao criar o snapshot de $$vm"; exit 1; }; \
	done; \
	echo "Snapshot criado (o snapshot 'so', usado pelo clean-k8s, não é tocado)."

restore: ## Restaura todas as VMs para o snapshot makefile_snapshot
	@vms=$$(virsh -c "$(LIBVIRT_URI)" list --all --name | grep '^$(VM_PREFIXO)-' || true); \
	if [ -z "$$vms" ]; then echo "Ainda não existem VMs."; exit 1; fi; \
	for vm in $$vms; do \
		if ! virsh -c "$(LIBVIRT_URI)" snapshot-list --name "$$vm" | grep -qx "$(SNAP)"; then \
			echo "Nenhum snapshot $(SNAP) em $$vm."; exit 1; \
		fi; \
	done; \
	echo "Restaurando snapshot para todas as VMs..."; \
	for vm in $$vms; do \
		virsh -c "$(LIBVIRT_URI)" snapshot-revert "$$vm" "$(SNAP)" >/dev/null || { echo "Falha ao restaurar $$vm"; exit 1; }; \
	done; \
	echo "Snapshot restaurado."
