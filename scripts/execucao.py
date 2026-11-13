#!/usr/bin/env python3
"""Roda as etapas do `make k8s-in-a-box` e grava logs e métricas da execução.

Uso:
    execucao.py <etapa> [<etapa> ...]

Cada etapa é um alvo do make (`up`, `cluster`, `ops`, `addons`, `exemplos`).
O script cria `.target/logs/AAAAMMDDhhmmss/` com:

    acoes.log      saída das etapas (make e Ansible, com profile_tasks e timer)
    tarefas/       um XML por playbook, com o tempo de cada tarefa (callback junit)
    etapas.tsv     etapa, início, fim, duração em segundos e status
    maquina.txt    descrição da máquina, das versões e do estado do cache
    recursos.tsv   CPU, memória, disco e rede do PC a cada 5 segundos
    resumo.txt     tempo por etapa, total baixado, pico de memória

As etapas rodam em sequência e param na primeira falha. O código de saída é o
da etapa que falhou. Só usa a biblioteca padrão e /proc; o amostrador é uma
thread deste processo e termina junto com ele.
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(RAIZ, ".target")
INTERVALO_S = 5


def agora():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ler(caminho):
    try:
        with open(caminho) as arq:
            return arq.read()
    except OSError:
        return ""


def comando(*args):
    """Saída de um comando (primeira linha), ou 'indisponível'."""
    try:
        saida = subprocess.run(args, capture_output=True, text=True, timeout=20, cwd=RAIZ)
    except (OSError, subprocess.TimeoutExpired):
        return "indisponível"
    texto = (saida.stdout or saida.stderr).strip()
    return texto.splitlines()[0] if texto else "indisponível"


# ──────────────────────────── leitura de /proc ────────────────────────────

def cpu_ocioso_total():
    campos = ler("/proc/stat").splitlines()[0].split()[1:]
    valores = [int(v) for v in campos]
    ocioso = valores[3] + (valores[4] if len(valores) > 4 else 0)
    return ocioso, sum(valores)


def meminfo():
    info = {}
    for linha in ler("/proc/meminfo").splitlines():
        nome, _, resto = linha.partition(":")
        info[nome] = int(resto.split()[0])  # kB
    return info


def interface_padrao():
    for linha in ler("/proc/net/route").splitlines()[1:]:
        campos = linha.split()
        if len(campos) > 1 and campos[1] == "00000000":
            return campos[0]
    return None


def bytes_rede(interface):
    for linha in ler("/proc/net/dev").splitlines()[2:]:
        nome, _, resto = linha.partition(":")
        if nome.strip() == interface:
            campos = resto.split()
            return int(campos[0]), int(campos[8])
    return 0, 0


# ──────────────────────────── amostrador ────────────────────────────

class Amostrador(threading.Thread):
    """Grava recursos.tsv a cada INTERVALO_S segundos até ser parado."""

    CABECALHO = ["t_s", "cpu_pct", "ram_usada_mib", "ram_disponivel_mib",
                 "swap_usada_mib", "disco_livre_gib", "rede_rx_bytes", "rede_tx_bytes"]

    def __init__(self, caminho, pasta_disco):
        super().__init__(daemon=True)
        self.caminho = caminho
        self.pasta_disco = pasta_disco
        self.parar = threading.Event()
        self.interface = interface_padrao()
        self.amostras = []

    def amostra(self, inicio, ocioso_ant, total_ant):
        ocioso, total = cpu_ocioso_total()
        delta = total - total_ant
        cpu = 100.0 * (1 - (ocioso - ocioso_ant) / delta) if delta > 0 else 0.0
        mem = meminfo()
        usada = (mem["MemTotal"] - mem["MemAvailable"]) / 1024
        swap = (mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)) / 1024
        disco = shutil.disk_usage(self.pasta_disco).free / 2**30
        rx, tx = bytes_rede(self.interface) if self.interface else (0, 0)
        linha = [round(time.time() - inicio, 1), round(cpu, 1), round(usada),
                 round(mem["MemAvailable"] / 1024), round(swap), round(disco, 1), rx, tx]
        return linha, ocioso, total

    def run(self):
        inicio = time.time()
        ocioso, total = cpu_ocioso_total()
        with open(self.caminho, "w") as arq:
            arq.write("\t".join(self.CABECALHO) + "\n")
            while True:
                linha, ocioso, total = self.amostra(inicio, ocioso, total)
                self.amostras.append(linha)
                arq.write("\t".join(str(v) for v in linha) + "\n")
                arq.flush()
                if self.parar.wait(INTERVALO_S):
                    # amostra final, para execuções mais curtas que o intervalo
                    linha, ocioso, total = self.amostra(inicio, ocioso, total)
                    self.amostras.append(linha)
                    arq.write("\t".join(str(v) for v in linha) + "\n")
                    break


# ──────────────────────────── maquina.txt ────────────────────────────

def tamanho_pasta(pasta):
    arquivos = 0
    total = 0
    for base, _, nomes in os.walk(pasta):
        for nome in nomes:
            try:
                total += os.path.getsize(os.path.join(base, nome))
                arquivos += 1
            except OSError:
                pass
    return arquivos, total


def variaveis_do_projeto():
    """Lê distro_base, plugin_cni e container_runtime do inventário ativo."""
    inventario = os.path.join(RAIZ, "inventario", "hosts.yml")
    if not os.path.exists(inventario):
        return {}
    try:
        saida = subprocess.run(["ansible-inventory", "-i", inventario, "--list"],
                               capture_output=True, text=True, timeout=60, cwd=RAIZ)
        hostvars = json.loads(saida.stdout)["_meta"]["hostvars"]
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError):
        return {}
    primeiro = next(iter(hostvars.values()), {})
    distros = sorted({h.get("distro_base", "?") for h in hostvars.values()})
    return {
        "hosts": ", ".join(sorted(hostvars)),
        "distro_base": ", ".join(distros),
        "plugin_cni": primeiro.get("plugin_cni", "?"),
        "container_runtime": primeiro.get("container_runtime", "?"),
    }


def descrever_maquina():
    cpu = next((l.split(":", 1)[1].strip() for l in ler("/proc/cpuinfo").splitlines()
                if l.startswith("model name")), "?")
    nucleos = os.cpu_count()
    mem = meminfo()
    disco = shutil.disk_usage(RAIZ)
    status_git = comando("git", "status", "--porcelain")
    variaveis = variaveis_do_projeto()
    linhas = [
        "# Máquina",
        "inicio: %s" % agora(),
        "so: %s" % (platform.platform()),
        "kernel: %s" % platform.release(),
        "cpu: %s" % cpu,
        "nucleos: %s" % nucleos,
        "ram_total_mib: %d" % (mem["MemTotal"] // 1024),
        "ram_disponivel_mib: %d" % (mem["MemAvailable"] // 1024),
        "disco_total_gib: %.0f" % (disco.total / 2**30),
        "disco_livre_gib: %.0f" % (disco.free / 2**30),
        "",
        "# Versões",
        "qemu: %s" % comando("qemu-system-x86_64", "--version"),
        "libvirt: %s" % comando("virsh", "--version"),
        "ansible: %s" % comando("ansible", "--version"),
        "make: %s" % comando("make", "--version"),
        "",
        "# Projeto",
        "commit: %s" % comando("git", "rev-parse", "HEAD"),
        "alteracoes_nao_commitadas: %s" % ("sim" if status_git not in ("", "indisponível") else "nao"),
        "CLUSTER: %s" % os.environ.get("CLUSTER", "(config.mk)"),
    ]
    linhas += ["%s: %s" % (k, v) for k, v in variaveis.items()]
    linhas += ["", "# Cache no início da execução (frio = vazio, quente = preenchido)"]
    for sub in ("imagens", "binarios", "oci"):
        arquivos, total = tamanho_pasta(os.path.join(TARGET, "cache", sub))
        linhas.append("cache/%s: %d arquivos, %.1f MiB" % (sub, arquivos, total / 2**20))
    return "\n".join(linhas) + "\n"


# ──────────────────────────── etapas ────────────────────────────

def rodar_etapa(etapa, log, ambiente):
    """Roda `make <etapa>`, copiando a saída ao terminal e ao log. Devolve o código."""
    processo = subprocess.Popen(
        ["make", etapa], cwd=RAIZ, env=ambiente,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
    )
    try:
        for linha in processo.stdout:
            sys.stdout.write(linha)
            sys.stdout.flush()
            log.write(linha)
            log.flush()
        return processo.wait()
    except KeyboardInterrupt:
        processo.terminate()
        try:
            processo.wait(timeout=15)
        except subprocess.TimeoutExpired:
            processo.kill()
        raise


def gravar_resumo(pasta, etapas, amostras, inicio_total, interrompido):
    linhas = ["# Resumo da execução", ""]
    linhas.append("%-14s %10s  %s" % ("etapa", "duracao_s", "status"))
    for nome, duracao, status in etapas:
        linhas.append("%-14s %10.1f  %s" % (nome, duracao, status))
    total = time.time() - inicio_total
    linhas += ["", "tempo_total_s: %.1f" % total]
    if amostras:
        baixados = max(0, amostras[-1][6] - amostras[0][6])
        linhas += [
            "baixado_mib: %.1f" % (baixados / 2**20),
            "pico_ram_usada_mib: %d" % max(a[2] for a in amostras),
            "menor_ram_disponivel_mib: %d" % min(a[3] for a in amostras),
            "cpu_media_pct: %.1f" % (sum(a[1] for a in amostras) / len(amostras)),
            "amostras: %d (a cada %ds)" % (len(amostras), INTERVALO_S),
        ]
    if interrompido:
        linhas.append("interrompida: sim")
    with open(os.path.join(pasta, "resumo.txt"), "w") as arq:
        arq.write("\n".join(linhas) + "\n")
    print("\n".join(linhas))


def main():
    etapas_pedidas = sys.argv[1:]
    if not etapas_pedidas:
        sys.exit(__doc__)

    marca = datetime.now().strftime("%Y%m%d%H%M%S")
    pasta = os.path.join(TARGET, "logs", marca)
    os.makedirs(os.path.join(pasta, "tarefas"), exist_ok=True)
    print("Logs da execução em %s" % pasta)

    with open(os.path.join(pasta, "maquina.txt"), "w") as arq:
        arq.write(descrever_maquina())

    ambiente = dict(os.environ)
    ambiente["ANSIBLE_CALLBACKS_ENABLED"] = "profile_tasks,timer,junit"
    ambiente["JUNIT_OUTPUT_DIR"] = os.path.join(pasta, "tarefas")

    amostrador = Amostrador(os.path.join(pasta, "recursos.tsv"), TARGET)
    amostrador.start()

    inicio_total = time.time()
    resultados = []
    codigo = 0
    interrompido = False
    try:
        with open(os.path.join(pasta, "acoes.log"), "w") as log, \
                open(os.path.join(pasta, "etapas.tsv"), "w") as tsv:
            tsv.write("etapa\tinicio\tfim\tduracao_s\tstatus\n")
            for etapa in etapas_pedidas:
                inicio = time.time()
                marca_inicio = agora()
                banner = "\n===== etapa %s: %s =====\n" % (etapa, marca_inicio)
                sys.stdout.write(banner)
                log.write(banner)
                try:
                    status = rodar_etapa(etapa, log, ambiente)
                except KeyboardInterrupt:
                    status = 130
                    interrompido = True
                duracao = time.time() - inicio
                tsv.write("%s\t%s\t%s\t%.1f\t%d\n" % (etapa, marca_inicio, agora(), duracao, status))
                tsv.flush()
                resultados.append((etapa, duracao, "ok" if status == 0 else "falhou (%d)" % status))
                if status != 0:
                    codigo = status
                    break
    finally:
        amostrador.parar.set()
        amostrador.join(timeout=INTERVALO_S + 2)
        gravar_resumo(pasta, resultados, amostrador.amostras, inicio_total, interrompido)
    sys.exit(codigo)


if __name__ == "__main__":
    main()
