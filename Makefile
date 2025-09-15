SHELL := /usr/bin/env bash
ARTEFATOS := artefatos

.DEFAULT_GOAL := help

help:
	@echo "Targets disponíveis:"
	@echo "  make up      - Sobe as VMs e recria a pasta artefatos/"
	@echo "  make down    - Interrompe as VMs"
	@echo "  make destroy - Destroi as VMs"
	@echo "  make clean   - Destroi as VMs e remove a pasta artefatos/"

up:
	rm -rf $(ARTEFATOS)
	mkdir -p $(ARTEFATOS)
	vagrant up

down:
	vagrant halt

destroy:
	vagrant destroy -f

clean: destroy
	rm -rf $(ARTEFATOS)
