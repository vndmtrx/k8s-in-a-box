#!/usr/bin/env bash
# Teste de 1 hora com várias interrupções da rede do nó, na mini, com o Cilium em eBPF
# (bpf.masquerade e bpf.tproxy). Para cada distro:
#
#   1. sobe a mini do zero e roda a esteira (cluster ops addons exemplos)
#   2. espera o cluster ficar pronto: pods prontos e 10 rodadas seguidas das sondas sem falha.
#      O relógio do teste (T0) começa aí, sem contar a subida do cluster.
#   3. segue a agenda abaixo, com sondas a cada ~3 s e a telemetria de cada nó
#   4. gera resumo.txt e remove as VMs
#
#   min  evento                                   recuperação
#    0   linha de base
#    5   nft flush no worker1                     11: reinicia o agente do Cilium do worker1
#   15   nft flush no nó dono do IP do Gateway    21: reinicia o agente desse nó
#   25   nftables.service liga e para (worker2)   31: reinicia o agente do worker2
#   35   nft flush no worker1 e no worker2        41: reinicia os dois agentes
#   45   reboot do worker2                        (nenhuma: mede a volta sozinha)
#   60   fim
#
# Uso (rode num terminal seu; leva ~1h25 por distro):
#   tmux new -s interrupcoes 'bash scripts/resiliencia/testa-interrupcoes.sh 2>&1 | tee ~/interrupcoes.out'
# Precisa das ferramentas do projeto (make bootstrap). Descrição e resultados: docs/resiliencia.md
# Variáveis:
#   DISTROS="debian almalinux"   distros, em ordem
#   FATOR=1                      multiplica a agenda (FATOR=0.2 faz um ensaio de 12 min)
#
# Resultado em .target/logs/interrupcoes-AAAAMMDDhhmm/<distro>/ (resumo.txt no topo).
# Não mexe no git nem no config.mk. Cria ansible/group_vars/all.yml para escolher a distro
# e o apaga ao sair. Enquanto roda, o notebook não suspende.
set -uo pipefail

DISTROS="${DISTROS:-debian almalinux}"
FATOR="${FATOR:-1}"
SCRIPT="$(readlink -f "$0")"
REPO="${REPO:-$(cd "$(dirname "$SCRIPT")/../.." && pwd)}"
RESUMIDOR="$(dirname "$SCRIPT")/resume-interrupcoes.py"

cd "$REPO" || { echo "Repositório não encontrado: $REPO" >&2; exit 1; }

if [ -z "${INTERRUPCOES_INIBIDO:-}" ] && command -v systemd-inhibit >/dev/null; then
  for oque in sleep:idle:handle-lid-switch sleep:idle; do
    if systemd-inhibit --what="$oque" true 2>/dev/null; then
      exec systemd-inhibit --what="$oque" --who=k8s-in-a-box --why="teste de interrupções" \
        env INTERRUPCOES_INIBIDO=1 bash "$SCRIPT" "$@"
    fi
  done
fi

if [ -e ansible/group_vars ]; then
  echo "ansible/group_vars já existe. Não vou sobrescrever; confira e apague antes." >&2
  exit 1
fi
[ -f "$RESUMIDOR" ] || { echo "Falta $RESUMIDOR" >&2; exit 1; }

export PATH="$REPO/.target/ferramentas/bin:$PATH" ANSIBLE_CONFIG=./ansible/.ansible.cfg
RAIZ="$REPO/.target/logs/interrupcoes-$(date +%Y%m%d%H%M)"
mkdir -p "$RAIZ"

limpar() { rm -f ansible/group_vars/all.yml; rmdir ansible/group_vars 2>/dev/null || true; }
trap 'limpar; echo "Interrompido. Logs em $RAIZ"; exit 130' INT TERM
trap limpar EXIT

declare -A IP=([manager1]=172.24.0.31 [worker1]=172.24.0.41 [worker2]=172.24.0.42 [kubox]=172.24.0.254)
NOS="manager1 worker1 worker2"

no() { local h=$1; shift; timeout "${TEMPO_SSH:-120}" ssh -F ssh_config -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "k8sbox@${IP[$h]}" "$@"; }
kc() { no kubox "$@"; }
agente() { kc "kubectl -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$1 -o name" 2>/dev/null; }
dono_gateway() { kc "kubectl -n kube-system get lease cilium-l2announce-kube-system-cilium-gateway-gateway-publico -o jsonpath='{.spec.holderIdentity}'" 2>/dev/null; }

uma_distro() {
  local DISTRO=$1 D="$RAIZ/$1"
  mkdir -p "$D/logs" "$D/fotos"
  local LT="$D/linha-do-tempo.txt"
  etapa() { echo "$(date +%H:%M:%S) $*" | tee -a "$LT"; }
  evento() { # evento <tipo> <nó> <detalhe>
    printf '%s\t%s\t%s\t%s\n' "$(date +%s.%N | cut -c1-14)" "$1" "$2" "${3:-}" >> "$D/eventos.tsv"
    etapa "evento: $1 $2 ${3:-}"
  }
  foto() { # foto <nome>: estado de cada nó e do cluster
    local p="$D/fotos/$(date +%H%M%S)-$1"; mkdir -p "$p"
    for h in $NOS; do
      no "$h" "sudo iptables-save" > "$p/$h-iptables.txt" 2>&1
      no "$h" "sudo nft list ruleset" > "$p/$h-nft.txt" 2>&1
      local a; a=$(agente "$h")
      [ -n "$a" ] || continue
      kc "kubectl -n kube-system exec $a -c cilium-agent -- cilium-dbg status --verbose" > "$p/$h-cilium-status.txt" 2>&1
      kc "kubectl -n kube-system exec $a -c cilium-agent -- hubble observe --last 2000 --to-port 8080 -o compact" > "$p/$h-hubble-8080.txt" 2>&1
      kc "kubectl -n kube-system exec $a -c cilium-agent -- hubble observe --last 500 --verdict DROPPED -o compact" > "$p/$h-hubble-drops.txt" 2>&1
    done
    kc "kubectl get pods -A -o wide" > "$p/pods.txt" 2>&1
    kc "kubectl get nodes -o wide" > "$p/nodes.txt" 2>&1
    kc "kubectl -n kube-system get lease -o wide" > "$p/leases.txt" 2>&1
  }
  em() { # em <minuto>: dorme até T0 + minuto * FATOR
    local alvo; alvo=$(python3 -c "print(int($T0 + $1 * 60 * $FATOR))")
    local agora; agora=$(date +%s)
    [ "$alvo" -gt "$agora" ] && sleep $((alvo - agora))
  }
  inicia_regras() {
    no "$1" "cat > /var/tmp/regras.sh && chmod +x /var/tmp/regras.sh && sudo rm -f /var/tmp/regras.parar" < "$D/regras.sh"
    no "$1" "sudo nohup setsid /var/tmp/regras.sh >/dev/null 2>&1 < /dev/null &"
  }
  inicia_monitor() { # quedas de pacote (cilium-dbg monitor --type drop), com hora
    local a; a=$(agente "$1")
    [ -n "$a" ] || return
    kc "nohup setsid bash -c 'kubectl -n kube-system exec $a -c cilium-agent -- cilium-dbg monitor --type drop 2>&1 | while IFS= read -r l; do echo \"\$(date +%s) \$l\"; done >> /tmp/drop-$1.log' >/dev/null 2>&1 < /dev/null &"
  }
  recupera() { # recupera <nó>...: reinicia o agente do Cilium e espera ele ficar pronto
    local h
    for h in "$@"; do evento recupera "$h" "delete pod do cilium-agent"; done
    for h in "$@"; do kc "kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=$h --wait=false" > /dev/null 2>&1; done
    sleep 5
    for h in "$@"; do
      kc "kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --field-selector spec.nodeName=$h --timeout=300s" > /dev/null 2>&1
      evento agente_pronto "$h"
      inicia_monitor "$h"
    done
  }

  : > "$LT"
  printf 'epoch\ttipo\tno\tdetalhe\n' > "$D/eventos.tsv"
  etapa "início ($DISTRO, FATOR=$FATOR)"
  limpar; mkdir -p ansible/group_vars
  echo "distro_base: \"$DISTRO\"" > ansible/group_vars/all.yml
  make --no-print-directory CLUSTER=mini init > /dev/null
  make --no-print-directory CLUSTER=mini clean-vms > "$D/logs/clean-inicial.log" 2>&1

  etapa "up"
  if ! timeout 1800 ansible-playbook ansible/provisiona.yml --tags criar -e apenas_sobe_com_cluster=true \
      > "$D/logs/up.log" 2>&1; then
    etapa "FALHOU no up"; return 1
  fi
  etapa "esteira (cluster ops addons exemplos)"
  if ! MAKEFLAGS="CLUSTER=mini" timeout 3000 python3 -B scripts/execucao.py cluster ops addons exemplos \
      > "$D/logs/esteira.log" 2>&1; then
    ln -sfn "../../$(basename "$(ls -td .target/logs/2*/ | head -1)")" "$D/execucao"
    etapa "FALHOU na esteira"; return 1
  fi
  ln -sfn "../../$(basename "$(ls -td .target/logs/2*/ | head -1)")" "$D/execucao"

  # Telemetria fixa.
  kc "kubectl -n kube-system get cm cilium-config -o yaml" > "$D/cilium-config.yml" 2>&1
  kc "kubectl -n kube-system exec $(agente worker1) -c cilium-agent -- cilium-dbg version" > "$D/cilium-version.txt" 2>&1
  kc "kubectl -n kube-system exec $(agente worker1) -c cilium-agent -- cilium-dbg status" > "$D/cilium-status-inicial.txt" 2>&1
  for h in $NOS; do
    no "$h" "grep PRETTY /etc/os-release; uname -r; sudo mokutil --sb-state 2>/dev/null; command -v getenforce >/dev/null && getenforce; sudo aa-status --enabled 2>/dev/null && echo apparmor ligado; systemctl is-enabled nftables 2>&1; systemctl cat nftables 2>/dev/null | grep -E '^Exec'" \
      > "$D/$h-so.txt" 2>&1
  done

  # Pods de sonda, um em cada worker; reiniciam sozinhos (o reboot do worker2 os derruba).
  for n in 1 2; do
    kc "kubectl -n default run sonda-w$n --image=busybox:1.37 --restart=Always --overrides='{\"spec\":{\"nodeName\":\"worker$n\"}}' -- sleep 86400" > /dev/null 2>&1
  done
  etapa "esperando o cluster ficar pronto"
  kc "kubectl -n default wait --for=condition=Ready pod/sonda-w1 pod/sonda-w2 --timeout=300s" > /dev/null 2>&1
  kc "kubectl wait --for=condition=Ready pods --all -A --field-selector=status.phase=Running --timeout=600s" > "$D/logs/pods-prontos.log" 2>&1

  local HELLO_W1 NP
  HELLO_W1=$(kc "kubectl -n exemplos get pod -l app=hello-app --field-selector spec.nodeName=worker1 -o jsonpath='{.items[0].status.podIP}'")
  NP=$(kc "kubectl -n kube-system get svc cilium-gateway-gateway-publico -o jsonpath='{.spec.ports[0].nodePort}'")
  etapa "hello-app no worker1: ${HELLO_W1:-nenhum}; NodePort do Gateway: $NP; IP do Gateway no: $(dono_gateway)"

  # Sondas: 1/0 por teste; nos testes do Gateway, o código HTTP (000 = sem resposta).
  cat > "$D/sonda.sh" <<EOF
#!/bin/bash
LOG=/tmp/sonda.log
ok() { "\$@" >/dev/null 2>&1 && echo 1 || echo 0; }
ex() { kubectl -n default exec "\$1" -- "\${@:2}"; }
http() { curl -s -o /dev/null -m 3 -w '%{http_code}' "\$1" 2>/dev/null; }
echo "epoch svc_w1 dns_w1 dnsext_w1 httpext_w1 podw2_para_w1 gw_ip gw_np_w1 gw_np_w2 gw_np_m1 svc_w2 dnsext_w2" > \$LOG
while [ ! -e /tmp/sonda.parar ]; do
  t=\$(date +%s.%N | cut -c1-14)
  echo "\$t \\
\$(ok ex sonda-w1 wget -q -T 2 -O /dev/null http://hello-svc.exemplos.svc.cluster.local) \\
\$(ok ex sonda-w1 timeout 3 nslookup kubernetes.default.svc.cluster.local) \\
\$(ok ex sonda-w1 timeout 4 nslookup example.com 1.1.1.1) \\
\$(ok ex sonda-w1 wget -q -T 4 --spider http://deb.debian.org/debian/) \\
\$(ok ex sonda-w2 wget -q -T 2 -O /dev/null http://${HELLO_W1:-127.0.0.1}:8080/) \\
\$(http http://172.24.0.110/) \\
\$(http http://172.24.0.41:$NP/) \\
\$(http http://172.24.0.42:$NP/) \\
\$(http http://172.24.0.31:$NP/) \\
\$(ok ex sonda-w2 wget -q -T 2 -O /dev/null http://hello-svc.exemplos.svc.cluster.local) \\
\$(ok ex sonda-w2 timeout 4 nslookup example.com 1.1.1.1)" >> \$LOG
  sleep 1
done
EOF
  cat > "$D/regras.sh" <<'EOF'
#!/bin/bash
LOG=/var/tmp/regras.log
[ -e $LOG ] || echo "epoch linhas_nft regras_cilium masquerade tproxy socket notrack" > $LOG
while [ ! -e /var/tmp/regras.parar ]; do
  s=$(iptables-save 2>/dev/null)
  echo "$(date +%s) $(nft list ruleset 2>/dev/null | wc -l) $(grep -c '^-A CILIUM' <<< "$s") $(grep -c -i 'masquerade' <<< "$s") $(grep -c TPROXY <<< "$s") $(grep -c -- '-m socket' <<< "$s") $(grep -c 'notrack' <<< "$s")" >> $LOG
  sleep 5
done
EOF
  no kubox "cat > /tmp/sonda.sh && chmod +x /tmp/sonda.sh && rm -f /tmp/sonda.parar /tmp/sonda.log /tmp/drop-*.log" < "$D/sonda.sh"
  no kubox "nohup setsid /tmp/sonda.sh >/dev/null 2>&1 < /dev/null &"
  for h in $NOS; do inicia_regras "$h"; inicia_monitor "$h"; done

  # Pronto = 10 rodadas seguidas com tudo ok (até 5 min).
  local limite=$(( $(date +%s) + 300 )) seguidas=0
  while [ "$(date +%s)" -lt "$limite" ]; do
    seguidas=$(kc "tail -10 /tmp/sonda.log" 2>/dev/null | awk 'NR>0 && $1!="epoch"{b=1; for(i=2;i<=NF;i++) if($i!="1" && $i!="200") b=0; s+=b} END{print s+0}')
    [ "$seguidas" -ge 10 ] && break
    sleep 10
  done
  T0=$(date +%s)
  evento pronto cluster "$seguidas de 10 rodadas sem falha"
  foto base

  em 5;  evento nft_flush worker1;          no worker1 "sudo nft flush ruleset"
  sleep 30; foto depois-flush-worker1
  em 11; recupera worker1
  sleep 30; foto depois-recupera-worker1

  em 15; local G; G=$(dono_gateway); [ -n "$G" ] || G=worker1
  evento nft_flush "$G" "dono do IP do Gateway";  no "$G" "sudo nft flush ruleset"
  sleep 30; foto "depois-flush-$G"
  em 21; recupera "$G"
  sleep 30; foto "depois-recupera-$G"

  em 25; evento nftables_service worker2 "systemctl start e stop nftables"
  no worker2 "sudo systemctl start nftables; sleep 3; sudo systemctl stop nftables; systemctl is-active nftables" >> "$D/logs/nftables-service.log" 2>&1
  sleep 30; foto depois-nftables-worker2
  em 31; recupera worker2
  sleep 30; foto depois-recupera-worker2

  em 35; evento nft_flush "worker1+worker2"
  no worker1 "sudo nft flush ruleset" & no worker2 "sudo nft flush ruleset"; wait
  sleep 30; foto depois-flush-workers
  em 41; recupera worker1 worker2
  sleep 30; foto depois-recupera-workers

  em 45; evento reboot worker2
  TEMPO_SSH=10 no worker2 "sudo systemctl reboot" > /dev/null 2>&1
  sleep 20
  until TEMPO_SSH=10 no worker2 true 2>/dev/null; do sleep 5; done
  evento ssh_voltou worker2
  inicia_regras worker2
  kc "kubectl wait --for=condition=Ready node/worker2 --timeout=600s" > /dev/null 2>&1; evento node_ready worker2
  kc "kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --field-selector spec.nodeName=worker2 --timeout=600s" > /dev/null 2>&1
  evento agente_pronto worker2; inicia_monitor worker2
  sleep 30; foto depois-reboot-worker2

  em 60; evento fim teste
  foto fim

  # Coleta final.
  no kubox "touch /tmp/sonda.parar"; sleep 8
  no kubox "cat /tmp/sonda.log" > "$D/sonda.log"
  for h in $NOS; do
    no kubox "cat /tmp/drop-$h.log 2>/dev/null" > "$D/logs/drop-$h.log"
    no "$h" "sudo touch /var/tmp/regras.parar"; sleep 1
    no "$h" "cat /var/tmp/regras.log" > "$D/regras-$h.log"
    kc "kubectl -n kube-system logs $(agente "$h") -c cilium-agent --since=90m" > "$D/logs/cilium-agent-$h.log" 2>&1
    kc "kubectl -n kube-system logs $(agente "$h") -c cilium-agent --previous --tail=3000" > "$D/logs/cilium-agent-$h-anterior.log" 2>&1
    kc "kubectl -n kube-system logs \$(kubectl -n kube-system get pod -l k8s-app=cilium-envoy --field-selector spec.nodeName=$h -o name) --since=90m" > "$D/logs/cilium-envoy-$h.log" 2>&1
    no "$h" "sudo journalctl -u kubelet --since '-90 min' --no-pager" > "$D/logs/kubelet-$h.log" 2>&1
    no "$h" "sudo journalctl -b -1 -u kubelet --no-pager 2>/dev/null | tail -300" > "$D/logs/kubelet-$h-boot-anterior.log" 2>&1
    no "$h" "sudo dmesg -T | tail -300" > "$D/logs/dmesg-$h.log" 2>&1
  done
  kc "kubectl get events -A --sort-by=.lastTimestamp" > "$D/logs/eventos-k8s.txt" 2>&1
  kc "kubectl -n kube-system get pods -o wide" > "$D/logs/kube-system-fim.txt" 2>&1

  python3 "$RESUMIDOR" "$D" > "$D/resumo.txt" 2>&1
  cat "$D/resumo.txt"

  etapa "removendo as VMs"
  make --no-print-directory CLUSTER=mini clean-vms > "$D/logs/clean-final.log" 2>&1
  etapa "fim ($DISTRO)"
}

for distro in $DISTROS; do
  uma_distro "$distro" || echo "$distro: falhou antes do teste; veja $RAIZ/$distro/linha-do-tempo.txt"
done
limpar
make --no-print-directory init > /dev/null 2>&1
echo "Logs em $RAIZ"
