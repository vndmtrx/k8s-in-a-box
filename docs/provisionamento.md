# Provisionamento: libvirt, cloud-init, Ansible e Makefile

A orquestração de todo o ciclo de vida do ambiente **k8s-in-a-box** usa quatro peças: o **libvirt** (com KVM) roda as VMs, o **cloud-init** prepara o sistema operacional no primeiro boot, o **Ansible** cria as VMs e instala o Kubernetes, e o **Makefile** reúne os comandos. Juntas, elas garantem que o "Kubernetes da maneira difícil" seja executado da "maneira mais reproduzível possível".

```
make up -> make bootstrap -> provisiona.yml (role infra-vms) -> libvirt -> cloud-init -> snapshot 'so'
        -> cluster.yml -> ops.yml -> addons.yml
```

Esta página aprofunda-se em como essas peças operam.

> ⚠️ Até 2026-11 o projeto criava as VMs com o Vagrant. Quem vem dessa versão deve rodar `vagrant destroy -f` na versão antiga antes do primeiro `make up`: as VMs e a rede antigas usam os mesmos IPs da `172.24.0.0/24`. Os domínios novos se chamam `k8sbox-<host>` (os do Vagrant eram `k8sbox_<host>`).

## libvirt e a role `infra-vms`

O playbook `ansible/provisiona.yml` lê o inventário ativo (`inventario/hosts.yml`) e trata cada host como um alvo, com conexão local. Por isso as VMs sobem em paralelo e `--limit kubox` funciona. A conexão com o libvirt é sempre `qemu:///system`, sem `sudo`; basta o usuário estar no grupo `libvirt`.

A role `infra-vms` faz, para cada VM:

| Passo | Task | O que faz |
|---|---|---|
| Chave SSH | `01-chave-ssh.yml` | cria `.target/cluster/ssh/id_ed25519`, se não existe |
| Imagem base | `02-imagem-base.yml` | baixa a imagem cloud da distro para `.target/cache/imagens/`, uma vez por distro, e confere o checksum publicado |
| Rede | `03-rede.yml` | cria a rede `k8sbox_mgmt` (NAT, `172.24.0.0/24`, sem DHCP) |
| Disco | `04-disco.yml` | cria `.target/vms/<host>/disco.qcow2` como overlay da imagem base |
| cloud-init | `05-cloudinit.yml` | gera `user-data`, `meta-data` e `network-config` e grava o `seed.iso` |
| Domínio | `06-dominio.yml` | define o domínio `k8sbox-<host>` e o liga |

Depois, o playbook espera o SSH e o fim do cloud-init (`cloud-init status --wait`), reinicia a VM se a distro pediu, desliga, tira o snapshot `so` e liga de novo. O snapshot `so` guarda o SO pronto, antes do Kubernetes. O `make clean-k8s` volta a ele e acerta o relógio com o `chronyc`.

Pontos do domínio:

* **Firmware:** UEFI com Secure Boot ligado nas duas distros. Cada VM tem o seu NVRAM em `.target/vms/<host>/nvram.fd`.
* **Rede:** uma placa virtio na `k8sbox_mgmt`. O MAC é derivado do IP (`52:54:00:18:00:1f` para `172.24.0.31`), e o cloud-init casa a placa por esse MAC e a renomeia para `mgmt0` (`interface_rede`). Assim o nome é o mesmo em qualquer distro, e o keepalived e o Cilium usam sempre `mgmt0`.
* **Console serial:** vai para `.target/vms/<host>/console.log`, com as mensagens do kernel e do cloud-init, mesmo quando o SSH não responde.
* **CPU e memória:** `host-model`, virtualização aninhada (`cpu_nested`) e memória `memfd` compartilhada. Os limites de cgroup (`cgroup_*`) são opcionais, por host.

As imagens base são fixadas por versão em `imagens_base` (`inventario/group_vars/all.yml`). O overlay de cada VM depende do conteúdo exato da base, então a versão nunca é `latest`. Para trocar de imagem, mude `url`, `arquivo` e `checksum_url` juntos e recrie as VMs (`make clean-vms`).

Fora do `.target`, o libvirt deixa dois arquivos por VM que só o `sudo` remove: `/var/log/libvirt/qemu/k8sbox-<host>.log` e `/etc/apparmor.d/libvirt/libvirt-<uuid>` (em hosts com AppArmor). Eles não atrapalham uma nova subida.

## cloud-init

O cloud-init cuida da camada de sistema operacional, no primeiro boot de cada VM. O `user-data` vem da role `infra-vms` e leva:

* o usuário `k8sbox`, com a chave SSH do cluster e `sudo` sem senha;
* os pacotes do SO, por grupo do inventário (`base` para toda VM; `cluster`, `loadbalancers`, `nfs` e `clientes` para os hosts desses grupos);
* fuso (`timezone_tz`), idioma (`locale_lang`) e o chrony, com `makestep` para acertar o relógio de uma vez;
* a atualização automática do SO, conforme `atualiza_sistema`: `nenhum`, `seguranca` (padrão, só correções de segurança) ou `todos`;
* no AlmaLinux, o SELinux em modo `permissive`.

As roles do Ansible não instalam pacotes do SO: elas só conferem se os comandos de que precisam existem e, se faltar algum, apontam o `user-data`.

> 💡 A atualização automática não atualiza o runtime de contêineres. O CRI-O e o containerd vêm como pacote estático, com a versão fixada em `versao_crio`, `versao_containerd` e `versao_runc`. Para subir a versão, mude a variável e recrie o cluster.

## Diferenças entre as distribuições

A variável `distro_base` escolhe a distribuição: `debian` (padrão) ou `almalinux`. Ela vale para o cluster inteiro e pode ser sobrescrita por host, em `configs/hosts-*.yml`; um cluster pode misturar as duas.

Todas as diferenças entre as distros ficam num só lugar: o dicionário `distros` em `ansible/infra-vms/vars/main.yml` (a "tabela das distros"), mais a imagem em `imagens_base`. Nenhuma role fora da `infra-vms` testa a distro.

| Item | Debian 13 | AlmaLinux 10 |
|---|---|---|
| Imagem | `debian-13-generic-amd64` (sha512) | `AlmaLinux-10-GenericCloud` (sha256) |
| Firmware (`boot`) | `efi`, Secure Boot ligado | `efi`, Secure Boot ligado |
| Chrony | `/etc/chrony/chrony.conf`, serviço `chrony` | `/etc/chrony.conf`, serviço `chronyd` |
| Reboot pendente | `test ! -e /var/run/reboot-required` | `needs-restarting -r` |
| Pacotes do cluster | `iproute2`, `conntrack`, `xz-utils`, `nfs-common` | `iproute`, `conntrack-tools`, `xz`, `nfs-utils`, `iptables-nft`, `kernel-modules-extra` |
| Servidor NFS | `nfs-kernel-server` | `nfs-utils` |
| Atualização automática | `unattended-upgrades`, só a origem `trixie-security` | `dnf-automatic`, `upgrade_type = security` |
| Proteção do SO | AppArmor da imagem, ligado | SELinux em `permissive` |
| Comandos no boot | `bootcmd` gera o idioma antes do cloud-init aplicá-lo; `runcmd` inicia o `qemu-guest-agent` | `runcmd` põe o SELinux em `permissive` |
| `atualiza_sistema: nenhum` | desliga a atualização que a imagem já traz ligada | não instala o `dnf-automatic` |
| DNS do kubelet | `/run/systemd/resolve/resolv.conf` (o `systemd-resolved` aponta o `/etc/resolv.conf` para `127.0.0.53`) | `/etc/resolv.conf` |

A imagem `generic` do Debian (e não a `genericcloud`) traz o kernel com todos os módulos, então não precisa de pacote de módulos extras. No AlmaLinux, o `kernel-modules-extra` puxa também um `kernel-core` novo, e o `dnf` baixa a lista inteira do repositório BaseOS: por isso o cloud-init do AlmaLinux leva cerca de 8 min por VM, contra cerca de 30 s do Debian.

O DNS do kubelet é escolhido pelo arquivo, não pela distro: a role `k8s-kubelet` usa `/run/systemd/resolve/resolv.conf` quando ele existe. Sem isso, o CoreDNS encaminharia as consultas para ele mesmo e cairia com `plugin/loop`.

### Como acrescentar uma terceira distribuição

1. **Imagem:** acrescente a distro em `imagens_base` (`inventario/group_vars/all.yml`), com `url`, `arquivo`, `checksum_url` e `checksum_algo`, numa versão fixa.
2. **Tabela:** acrescente uma entrada em `distros` (`ansible/infra-vms/vars/main.yml`) com todas as chaves descritas no topo do arquivo: `boot`, `chrony_conf`, `chrony_servico`, `reboot_pendente`, `pacotes` (os cinco grupos), `runcmd`, `bootcmd` e `atualizacao`, além de `sem_atualizacao` se a imagem já traz a atualização automática ligada.
3. **Pacotes:** os pacotes de cada grupo precisam entregar os comandos que as roles conferem, como `nft`, `iptables`, `conntrack`, `socat`, `skopeo`, `chronyc`, `haproxy`, `keepalived` e `exportfs`. Se faltar algum, a role para com uma mensagem que diz qual.
4. **Requisitos da imagem:** cloud-init com o datasource NoCloud e `network-config` versão 2 (com `match` por MAC e `set-name`), systemd, `python3` em `/usr/bin/python3` e boot em UEFI com Secure Boot. Se a imagem não subir em UEFI, use `boot: bios`.
5. **Teste aos poucos:** primeiro uma VM só (ponha `distro_base` num host), depois a `mini` inteira (`make k8s-in-a-box`) e, por fim, a conformidade na `completo` (`make teste-conformidade CLUSTER=completo`).

## Ansible

Depois das VMs, o **Ansible** instala o Kubernetes. O provisionamento é puramente declarativo.

* **O Playbook Mestre (`ansible/cluster.yml`):**
  A espinha dorsal que comanda a execução metódica de todas as roles na ordem exata de dependências. Ele executa: geração de certificados (`infra-pki`), base de SO, balanceador, kubelet (iniciado antes do etcd para gerenciar os static pods do control plane), etcd e control plane (como Static Pods). A rede (Cilium, que também substitui o `kube-proxy`) é aplicada pelo playbook `ops.yml` após o cluster estar ativo, e os complementos pelo `addons.yml`.
* **Injeção de Variáveis:**
  Todo o comportamento dos playbooks deriva do arquivo universal `inventario/group_vars/all.yml`. Esse padrão permite que o usuário mude versões, a distro e o runtime apenas manipulando esse arquivo, sem tocar nos códigos da pasta `ansible/`.
* **Configuração Personalizada (`.ansible.cfg`):**
  Um arquivo de configuração focado no contexto do projeto. Ele grava o log, o cache de fatos e os sockets SSH em `.target/ansible/` e usa o `ssh_config` da raiz, que desliga a verificação de host-key: as VMs são recriadas com frequência e repetem os mesmos IPs.

## Otimizações de Provisionamento

Para otimizar o tempo de provisionamento e mitigar o uso desnecessário de banda de internet, o projeto implementa duas estratégias:

### 1. Cache Local de Imagens de Containers
As imagens do sistema (Kubernetes, pause, etcd, etc.) são pesadas e seu download repetido a cada nova criação de cluster consome banda e tempo significativos. O projeto resolve isso via cache no host de desenvolvimento:
* **Detecção:** A role `k8s-kubelet` (`tasks/07-download-imagens-sistema.yml`) verifica se os tarballs das imagens necessárias já existem no host, em `.target/cache/oci/`.
* **Download Centralizado:** Se ausente, o primeiro manager (`manager1`) faz o download da imagem via `skopeo copy` direto do registro de container para um tarball local e envia o arquivo de volta para o host de desenvolvimento (via `ansible.builtin.fetch`).
* **Distribuição e Carga:** Para cada nó no cluster, o Ansible copia o tarball do host local para a VM e o importa diretamente no runtime de container configurado:
  * No **CRI-O**: A importação ocorre via `skopeo copy` para o `containers-storage`.
  * No **Containerd**: A importação ocorre via `ctr -n k8s.io images import`.
* **Benefício:** Permite um provisionamento rápido ("offline-ready") após o primeiro download.

### 2. Extração do `etcdctl` da imagem do etcd em cache
Tradicionalmente, a instalação da ferramenta de gerenciamento do `etcd` (`etcdctl`) exigiria o download do arquivo compactado completo de lançamento do etcd na internet para descompactar apenas um binário. No projeto:
* A imagem do etcd já está no cache OCI do host (`.target/cache/oci/etcd-<versão>.tar`, formato `docker-archive`), deixada pela role `k8s-kubelet`.
* O script `ansible/ops-ferramentas/files/extrai-do-oci.py` percorre as camadas da imagem, da mais nova para a mais antiga, e grava o `usr/local/bin/etcdctl` em `.target/cache/binarios/etcdctl-<versão>`.
* O Ansible instala esse executável no bastion host `kubox`.
* **Benefício:** o `etcdctl` tem exatamente a versão do container do etcd, sem baixar o tarball de distribuição e sem depender do container runtime (CRI-O ou containerd) nem de um manager no ar.

## Makefile

Digitar comandos longos de Ansible repetidamente gera atrito e abre espaço para erros de digitação. O **Makefile** reúne os comandos do dia a dia.

| Alvo | O que faz |
|---|---|
| `make init` / `make status` | ativa e mostra a topologia (symlink `inventario/hosts.yml` para `configs/hosts-<CLUSTER>.yml`) |
| `make bootstrap` | confere os pacotes do SO (e mostra o `apt`/`dnf` do que falta), instala as ferramentas do projeto e confere a collection `community.libvirt`, o grupo `libvirt`, `/dev/kvm`, o acesso do QEMU ao `.target`, a RAM e o disco |
| `make ferramentas` | instala o Ansible, o `netaddr` e o `ansible-lint` com o `pipx` em `.target/ferramentas`, em versões fixas |
| `make up` / `make down` | cria e liga as VMs (menos o `kubox`) / desliga sem remover |
| `make ops-up` | cria e liga só o `kubox` |
| `make ssh-<host>` | abre SSH numa VM (ex.: `make ssh-manager1`) |
| `make cluster`, `make infra`, `make control-plane` | instalam o cluster inteiro ou uma parte dele |
| `make ops`, `make cni`, `make addons`, `make exemplos` | ferramentas do `kubox`, Cilium, addons e exemplos |
| `make k8s-in-a-box` | esteira inteira, com logs em `.target/logs/AAAAMMDDhhmmss/` |
| `make build` | a mesma esteira, sem logs |
| `make conformidade` / `make teste-conformidade` | Sonobuoy no cluster no ar / cluster do zero, teste e remoção das VMs |
| `make snapshot` / `make restore` | snapshot `makefile_snapshot` de todas as VMs / volta a ele |
| `make clean-k8s` ... `make purge` | limpeza em camadas (tabela no [README](../README.md#destruindo-o-ambiente)) |

Através desta combinação, uma rede inteira virtual com suas complexidades se materializa num computador pessoal com apenas dois comandos: `make bootstrap` e `make k8s-in-a-box`.
