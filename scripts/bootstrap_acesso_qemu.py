#!/usr/bin/env python3
"""Confere se o usuário do QEMU consegue atravessar os diretórios até uma pasta.

Os discos, a ISO do cloud-init e as imagens base ficam em `.target/`, dentro da
pasta do usuário. O libvirt roda o QEMU com um usuário de sistema (hoje
`libvirt-qemu`) e esse usuário precisa de `x` em cada diretório do caminho.

Uso:
    bootstrap_acesso_qemu.py <pasta> [<uri-libvirt>]

Imprime uma linha por problema, com o comando `setfacl` que resolve, e sai com
código 1. Sai com 0 quando o caminho está livre.

O uid do QEMU vem de `virsh capabilities` (modelo de segurança `dac`, rótulo
base `+UID:+GID`). Só usa a biblioteca padrão e o `getfacl`, quando existir.
"""
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def uid_do_qemu(uri):
    """Lê o uid e o gid base do QEMU nas capacidades do libvirt."""
    saida = subprocess.run(
        ["virsh", "-c", uri, "capabilities"],
        capture_output=True, text=True, check=True,
    ).stdout
    raiz = ET.fromstring(saida)
    for modelo in raiz.iter("secmodel"):
        if (modelo.findtext("model") or "").strip() != "dac":
            continue
        for rotulo in modelo.iter("baselabel"):
            if rotulo.get("type") == "kvm":
                achado = re.match(r"^\+?(\d+):\+?(\d+)$", (rotulo.text or "").strip())
                if achado:
                    return int(achado.group(1)), int(achado.group(2))
    raise RuntimeError("não achei o rótulo base 'dac' do QEMU em 'virsh capabilities'")


def grupos_do_uid(uid, gid):
    """Grupos do usuário do QEMU (principal + suplementares), se ele existir."""
    grupos = {gid}
    try:
        import pwd
        nome = pwd.getpwuid(uid).pw_name
        grupos.update(os.getgrouplist(nome, gid))
    except (KeyError, ImportError):
        pass
    return grupos


def ler_acl(caminho):
    """Devolve (dono, grupo, entradas) de `getfacl -p -n`, ou None sem getfacl."""
    if not shutil.which("getfacl"):
        return None
    saida = subprocess.run(
        ["getfacl", "-p", "-n", caminho], capture_output=True, text=True, check=True
    ).stdout
    dono = grupo = None
    entradas = []
    for linha in saida.splitlines():
        linha = linha.strip()
        if linha.startswith("# owner:"):
            dono = int(linha.split(":", 1)[1])
        elif linha.startswith("# group:"):
            grupo = int(linha.split(":", 1)[1])
        else:
            corpo = linha.split("#", 1)[0].strip()
            if corpo:
                tipo, qualificador, perm = corpo.split(":")[:3]
                entradas.append((tipo, qualificador, perm.strip()[:3]))
    return dono, grupo, entradas


def pode_atravessar(acl, uid, grupos):
    """Aplica o algoritmo de ACL POSIX para o bit `x` de um uid."""
    dono, grupo_dono, entradas = acl
    permissao = {(t, q): p for t, q, p in entradas}
    mascara = permissao.get(("mask", ""), "rwx")
    if uid == dono:
        return "x" in permissao.get(("user", ""), "---")
    if ("user", str(uid)) in permissao:
        return "x" in permissao[("user", str(uid))] and "x" in mascara
    encontrou_grupo = False
    for gid in grupos:
        chave = ("group", "") if gid == grupo_dono else ("group", str(gid))
        if chave in permissao:
            encontrou_grupo = True
            if "x" in permissao[chave] and "x" in mascara:
                return True
    if encontrou_grupo:
        return False
    return "x" in permissao.get(("other", ""), "---")


def pode_atravessar_por_modo(caminho, uid, grupos):
    """Alternativa sem getfacl: usa só os bits de modo."""
    info = os.stat(caminho)
    if uid == info.st_uid:
        return bool(info.st_mode & 0o100)
    if info.st_gid in grupos:
        return bool(info.st_mode & 0o010)
    return bool(info.st_mode & 0o001)


def diretorios_do_caminho(pasta):
    absoluto = os.path.abspath(pasta)
    partes = absoluto.strip("/").split("/")
    caminhos = ["/"]
    for i in range(1, len(partes) + 1):
        caminhos.append("/" + "/".join(partes[:i]))
    return caminhos


def acl_indeterminada(acl):
    """True se a ACL tem uid sem mapeamento (-1), como em contêiner ou user namespace."""
    return any(q.isdigit() and int(q) >= 2**31 for _, q, _ in acl[2])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pasta = sys.argv[1]
    uri = sys.argv[2] if len(sys.argv) > 2 else "qemu:///system"
    uid, gid = uid_do_qemu(uri)
    grupos = grupos_do_uid(uid, gid)
    problemas = 0
    for diretorio in diretorios_do_caminho(pasta):
        if not os.path.isdir(diretorio):
            continue
        acl = ler_acl(diretorio)
        if acl and acl_indeterminada(acl) and not pode_atravessar(acl, uid, grupos):
            print("aviso: %s tem ACL com uid sem mapeamento; não consegui conferir o acesso do QEMU "
                  "(rode 'make bootstrap' num terminal fora de contêiner)" % diretorio)
            continue
        livre = (pode_atravessar(acl, uid, grupos) if acl
                 else pode_atravessar_por_modo(diretorio, uid, grupos))
        if not livre:
            problemas += 1
            print("o usuário do QEMU (uid %d) não atravessa %s -> sudo setfacl -m u:%d:x %s"
                  % (uid, diretorio, uid, diretorio))
    sys.exit(1 if problemas else 0)


if __name__ == "__main__":
    main()
