#!/usr/bin/env python3
"""Soma os recursos exigidos pela topologia ativa.

Lê a saída de `ansible-inventory --list` (JSON) em stdin e imprime, em uma única
linha separada por espaços:

    <ram_total_mib> <disco_total_gib> <numero_de_hosts>

RAM vem de `memory` (MiB) de cada host. O disco vem de `disk_size` por host,
caindo no default global (variável de ambiente DISK_SIZE_DEFAULT, padrão 20G)
quando o host não define o seu. Usado pelo alvo `make bootstrap`.

A variável de ambiente HOSTS_EXISTENTES (nomes separados por espaço) lista hosts
cujas VMs já estão ligadas: eles não entram na soma, para que repetir `make up`
com o cluster no ar não falhe por falta de RAM.
"""
import json
import os
import re
import sys

_UNIDADES_GIB = {
    "K": 1 / 1048576.0,
    "M": 1 / 1024.0,
    "G": 1.0,
    "T": 1024.0,
}


def para_gib(valor):
    """Converte um tamanho (ex.: '20G', '512M', '2048') para GiB (float)."""
    texto = str(valor).strip().upper()
    casamento = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?)I?B?$", texto)
    if not casamento:
        return 0.0
    numero = float(casamento.group(1))
    unidade = casamento.group(2) or "G"  # sem sufixo assume-se GiB
    return numero * _UNIDADES_GIB[unidade]


def main():
    try:
        dados = json.load(sys.stdin)
    except json.JSONDecodeError as erro:
        sys.exit("inventário efetivo inválido: %s" % erro)

    hostvars = dados.get("_meta", {}).get("hostvars", {})
    if not hostvars:
        sys.exit("inventário efetivo sem hosts")

    disco_default = os.environ.get("DISK_SIZE_DEFAULT", "20G")
    existentes = set(os.environ.get("HOSTS_EXISTENTES", "").split())
    ram_mib = 0
    disco_gib = 0.0
    contados = 0
    for nome, host in hostvars.items():
        if nome in existentes:
            continue
        contados += 1
        ram_mib += int(host.get("memory", 0))
        disco_gib += para_gib(host.get("disk_size", disco_default))

    print("%d %.0f %d" % (ram_mib, round(disco_gib), contados))


if __name__ == "__main__":
    main()
