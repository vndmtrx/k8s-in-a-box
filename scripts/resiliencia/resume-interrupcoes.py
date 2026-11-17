#!/usr/bin/env python3
"""Resume uma pasta do testa-interrupcoes.sh.

Uso: python3 resume-interrupcoes.py <pasta-da-distro>

Lê sonda.log, eventos.tsv e regras-<nó>.log e imprime, por janela da agenda, a taxa de
sucesso de cada sonda, o tempo até a primeira falha e o tempo até a última falha (a volta),
contados a partir do começo da janela. Os tempos são em segundos.
"""
import os
import sys

D = sys.argv[1]
OK = {"1", "200"}


def ler_tabela(caminho, sep=None):
    if not os.path.exists(caminho):
        return [], []
    linhas = [l.rstrip("\n") for l in open(caminho, encoding="utf-8", errors="replace") if l.strip()]
    if not linhas:
        return [], []
    cab = linhas[0].split(sep)
    dados = []
    for l in linhas[1:]:
        c = l.split(sep)
        if c[0] == cab[0]:
            continue
        try:
            float(c[0])
        except ValueError:
            continue
        dados.append(c)
    return cab, dados


cab, sondas = ler_tabela(os.path.join(D, "sonda.log"))
_, eventos = ler_tabela(os.path.join(D, "eventos.tsv"), "\t")
if not sondas or not eventos:
    sys.exit("sem dados em %s" % D)
nomes = cab[1:]

t0 = next(float(e[0]) for e in eventos if e[1] == "pronto")
# Janelas: cada evento da agenda (e cada recuperação) abre uma janela que vai até o próximo.
marcos = [e for e in eventos if e[1] in ("pronto", "nft_flush", "nftables_service", "reboot",
                                         "recupera", "fim")]
# Recuperações de vários nós ao mesmo tempo viram um marco só.
janelas = []
for e in marcos:
    t = float(e[0])
    if janelas and e[1] == "recupera" and janelas[-1][1] == "recupera" and t - janelas[-1][0] < 15:
        janelas[-1][2] += "+" + e[2]
        continue
    janelas.append([t, e[1], e[2]])

print("Distro: %s" % os.path.basename(os.path.normpath(D)))
print("T0 (cluster pronto): %s" % next(e[3] for e in eventos if e[1] == "pronto"))
print("Sondas: %d rodadas, uma a cada %.1f s em média" % (
    len(sondas), (float(sondas[-1][0]) - float(sondas[0][0])) / max(1, len(sondas) - 1)))
print()
print("Legenda: %ok | 1ª falha (s) | última falha (s), contadas do começo da janela")
print("         gw_* = Gateway (IP .110 ou NodePort de cada nó); um '-' = nenhuma falha")
print()

for i, (ini, tipo, no) in enumerate(janelas):
    if tipo == "fim":
        break
    fim = janelas[i + 1][0]
    linhas = [s for s in sondas if ini <= float(s[0]) < fim]
    rotulo = "base" if tipo == "pronto" else "%s %s" % (tipo, no)
    print("── T0+%5.1f min  %-32s (%d rodadas, %.0f s)" % ((ini - t0) / 60, rotulo, len(linhas), fim - ini))
    if not linhas:
        continue
    for j, nome in enumerate(nomes, start=1):
        vals = [(float(s[0]) - ini, s[j] if j < len(s) else "?") for s in linhas]
        bons = sum(1 for _, v in vals if v in OK)
        falhas = [t for t, v in vals if v not in OK]
        codigos = sorted({v for _, v in vals if v not in OK})
        if falhas:
            print("   %-14s %4.0f%%  %6.0f  %6.0f   %s" % (
                nome, 100.0 * bons / len(vals), falhas[0], falhas[-1], ",".join(codigos)))
        else:
            print("   %-14s %4.0f%%       -       -" % (nome, 100.0))
    print()

print("Eventos")
for e in eventos:
    print("   T0%+8.0f s  %-16s %-16s %s" % (float(e[0]) - t0, e[1], e[2], e[3] if len(e) > 3 else ""))
print()

print("Regras no nó (mudanças: epoch linhas_nft regras_cilium masquerade tproxy socket notrack)")
for f in sorted(os.listdir(D)):
    if not (f.startswith("regras-") and f.endswith(".log")):
        continue
    _, linhas = ler_tabela(os.path.join(D, f))
    print("   %s" % f[7:-4])
    ant = None
    for l in linhas:
        chave = tuple(l[1:])
        if chave != ant:
            print("      T0%+8.0f s  %s" % (float(l[0]) - t0, " ".join(l[1:])))
            ant = chave
