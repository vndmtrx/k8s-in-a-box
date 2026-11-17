# Resiliência da rede do nó

Esta página reúne os testes de resiliência da rede dos nós: o que acontece com o cluster quando as regras de firewall de um nó somem ou quando um nó reinicia, e como voltar ao normal. Ela serve de base para os tutoriais de resiliência e de gerenciamento do cluster.

Todos os números vêm de medidas na topologia `mini` (1 manager, 2 workers), com CRI-O, Kubernetes `v1.37.2` e Cilium `v1.20.4`, em novembro de 2026. Cada caso rodou uma vez só por distro, então os números mostram o comportamento, não uma média.

## O que o Cilium ainda deixa no iptables

O Cilium faz em eBPF quase todo o trabalho de rede: os Services (no lugar do `kube-proxy`), o roteamento entre nós e, desde 2026-11-17, o **masquerade** (a troca do IP do pod pelo do nó na saída para fora do cluster) e o **TPROXY** (o desvio do tráfego da Gateway API para o Envoy do nó). Essas duas últimas estão ligadas em `ansible/cni-cilium/templates/cilium-values.yml.j2`:

```yaml
bpf:
  masquerade: true
  tproxy: true
```

Mesmo assim, o Envoy do nó ainda depende de algumas regras do iptables (gravadas pelo `iptables-nft`), como a marcação de sockets transparentes (`-m socket --transparent`, na tabela `mangle`) e o `NOTRACK` do tráfego do proxy (tabela `raw`). Com o eBPF ligado, sobram 15 regras `CILIUM_*` em cada nó; antes, eram 24.

Para conferir o modo do datapath num nó:

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -E "Masquerading|Routing"
# Routing:      Network: Tunnel [vxlan]   Host: BPF
# Masquerading: BPF   [mgmt0]   172.25.1.0/24  [IPv4: Enabled, IPv6: Disabled]
```

## Exercício: apagar as regras de firewall de um nó

```bash
make ssh-worker1
sudo nft flush ruleset          # apaga todas as regras nftables/iptables do nó
```

O mesmo efeito acontece quando o serviço `nftables` para ou recarrega, porque a unit dele roda `ExecStop=/usr/sbin/nft flush ruleset`. **Por isso o projeto não liga o `nftables.service` nos nós.**

### O que quebra e o que segue

| Teste, depois do flush | Regras no iptables (Debian) | eBPF (Debian) | eBPF (AlmaLinux) |
|---|---|---|---|
| Service ClusterIP, DNS do cluster, pod para pod entre nós | 100% | 100% | 100% |
| Saída dos pods do nó para a internet (DNS e HTTP) | **0%** | 100% | 100% |
| Gateway entrando pelo nó afetado (IP `.110` ou NodePort) | **0%** | 38% a 65% | 60% a 81% |
| Gateway entrando por outro nó | 100% | 100% | 100% |
| Regras `CILIUM_*` no nó | 24 → 0 | 15 → 0 | 15 → 0 |
| Volta sozinho | em 20 min 25 s | não voltou em 6 min | não voltou em 6 min |

* Com o eBPF, **a saída dos pods não depende mais do iptables**.
* **O Gateway que entra pelo nó afetado falha em parte das requisições** (`000`, sem resposta, ou `503`). Os outros nós seguem servindo o Gateway normalmente.
* O IP do Gateway (`172.24.0.110`) é anunciado por um nó só, o dono do lease `cilium-l2announce-kube-system-cilium-gateway-gateway-publico`. Se o flush cair nesse nó, o Gateway pelo IP também falha em parte.
* **Em ~1 min**, o kubelet percebe o flush pelas suas chains de canário (`KUBE-KUBELET-CANARY`) e recria só as próprias regras (`"Reloading after iptables flush"` no log do kubelet). As do Cilium não voltam com elas.
* Com as regras no iptables, o Cilium refez as suas sozinho em 20 min 25 s. Com o eBPF, não refez em 6 min. O log do agente não mostra o que dispara essa recriação, e o agente não tem uma opção para mudar esse intervalo ([cilium#16644](https://github.com/cilium/cilium/issues/16644)).

### Como voltar

Reinicie o agente do Cilium do nó afetado. Ele grava todas as regras ao subir:

```bash
kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=<nó>
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --field-selector spec.nodeName=<nó>
```

O agente fica pronto em ~13 s. O NodePort do nó ainda falha em algumas requisições por 5 a 20 s, e depois volta a 100%. Se o nó era o dono do IP do Gateway, o anúncio passa para outro nó enquanto o agente reinicia, e o Gateway pelo IP volta em ~1 s.

## Teste de 1 hora com várias interrupções

O teste roda a agenda abaixo num cluster já pronto. O relógio (T0) começa quando todos os pods estão prontos e 10 rodadas seguidas das sondas passam sem falha, então a subida do cluster não entra na conta.

| Min | Interrupção | Recuperação |
|---|---|---|
| 0 | linha de base | — |
| 5 | `nft flush` no worker1 | min 11: reinicia o agente do worker1 |
| 15 | `nft flush` no nó dono do IP do Gateway | min 21: reinicia o agente desse nó |
| 25 | `nftables.service` liga e para no worker2 | min 31: reinicia o agente do worker2 |
| 35 | `nft flush` no worker1 e no worker2 juntos | min 41: reinicia os dois agentes |
| 45 | reboot do worker2 | nenhuma: mede a volta sozinha |
| 60 | fim | — |

### Resultado (2026-11-17, com o eBPF ligado)

% de sucesso do Gateway pelo nó afetado em cada janela. Todas as outras sondas (Service, DNS do cluster, saída para a internet, pod a pod, Gateway por outro nó) ficaram em 100% nas interrupções de firewall.

| Janela | Debian | AlmaLinux |
|---|---|---|
| `nft flush` no worker1 | 53% | 81% |
| `nft flush` no dono do IP do Gateway (IP `.110` / NodePort) | 38% / 65% | 69% / 69% |
| `nftables.service` liga e para | 48% | 73% |
| `nft flush` nos dois workers | 42% a 56% | 60% a 72% |
| Depois de reiniciar o agente | 99% a 100% | 99% a 100% |

Reboot do worker2:

| | Debian | AlmaLinux |
|---|---|---|
| SSH de volta | 47 s | 51 s |
| Agente do Cilium pronto | 61 s | 68 s |
| Sondas do worker2 de volta | 94 s | 200 s |
| Regras do Cilium | voltaram sozinhas | voltaram sozinhas |

O reboot se cura sozinho: o agente do Cilium grava as regras ao subir. As sondas do worker2 levam mais tempo que o agente porque o próprio pod de sonda também reinicia. A diferença entre as distros no reboot ainda não foi investigada.

### Como rodar

O teste fica em `scripts/resiliencia/` e roda num terminal seu (~1h25 por distro, com a subida do cluster):

```bash
tmux new -s interrupcoes 'bash scripts/resiliencia/testa-interrupcoes.sh 2>&1 | tee ~/interrupcoes.out'
```

| Variável | Padrão | Uso |
|---|---|---|
| `DISTROS` | `debian almalinux` | distros, em ordem |
| `FATOR` | `1` | multiplica a agenda; `FATOR=0.2` faz um ensaio de 12 min |

Ele precisa das ferramentas do projeto (`make bootstrap`) e não mexe no git nem no `config.mk`. Para escolher a distro, cria `ansible/group_vars/all.yml` e o apaga ao sair. No fim, remove as VMs.

### O que ele coleta

Em `.target/logs/interrupcoes-AAAAMMDDhhmm/<distro>/`:

| Arquivo | Conteúdo |
|---|---|
| `resumo.txt` | por janela e por sonda: % de sucesso, 1ª e última falha; eventos; mudanças nas regras |
| `sonda.log` | 11 sondas a cada ~2,5 s, a partir do `kubox` (Gateway com o código HTTP) |
| `eventos.tsv` | hora de cada interrupção e recuperação |
| `regras-<nó>.log` | regras nft, `CILIUM_*`, masquerade, TPROXY, socket e `NOTRACK`, a cada 5 s |
| `fotos/` | antes e 30 s depois de cada evento: `iptables-save`, `nft list ruleset`, `cilium-dbg status --verbose`, Hubble (porta 8080 e drops), pods, nós e leases |
| `logs/` | agente do Cilium (e o anterior), Envoy, kubelet (e o do boot anterior), `dmesg`, quedas de pacote (`cilium-dbg monitor --type drop`) e eventos do Kubernetes |
| `cilium-config.yml`, `cilium-version.txt` | configuração do Cilium |
| `<nó>-so.txt` | distro, kernel, Secure Boot, SELinux/AppArmor e o estado do `nftables.service` |

Para refazer o resumo de uma pasta: `python3 scripts/resiliencia/resume-interrupcoes.py <pasta-da-distro>`.

## Pontos em aberto

* Qual das regras restantes o Envoy precisa, e se o Cilium tem uma opção para dispensá-la.
* Por que as sondas do worker2 levam mais tempo para voltar no AlmaLinux depois do reboot.
* Os mesmos testes na topologia `completo`, com 3 managers.
