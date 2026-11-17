# Visão Geral da Estrutura do Cluster

O **k8s‑in‑a‑box** é um ambiente Kubernetes completo, construído de forma manual e automatizado via Ansible. Este cluster foi concebido para oferecer alta disponibilidade, armazenamento persistente, capacidade de gerenciamento e componentes adicionais, facilitando testes e estudos de Kubernetes.

## Componentes Principais

### Balanceador de carga (HAProxy + Keepalived)

* **Função:** distribuir as requisições para o control plane (API Server) e para o etcd, garantindo alta disponibilidade.
* **Tecnologias:**

  * **HAProxy**, configurado via Ansible para atuar como proxy reverso; inclui templates e validação de configuração antes de habilitar o serviço.
  * **Keepalived**, responsável por manter um VIP (virtual IP) ativo para failover automático.

### Servidor NFS

* **Função:** fornecer armazenamento persistente para o cluster, usado por um StorageClass dinâmico.
* **Configuração:** exporta o diretório `/srv/nfs/k8s`, configurado via template `/etc/exports`; o serviço `nfs-server` é mantido ativo. O pacote do servidor vem do cloud-init (`nfs-kernel-server` no Debian, `nfs-utils` no AlmaLinux).

### Managers (3 nós)

* **Função:** compõem o control plane do Kubernetes e mantêm o banco de dados do cluster.
* **Componentes instalados:**

  * **Etcd**: banco de dados distribuído com certificados configurados para mTLS, executando como Static Pod gerenciado pelo kubelet.
  * **Componentes do Control Node**: `kube‑apiserver`, `kube‑controller‑manager` e `kube‑scheduler`. São executados como **Static Pods** declarados no diretório `/opt/k8s-in-a-box/manifests` e gerenciados diretamente pelo Kubelet local (método padrão e único do cluster).
  * **Componentes extras instalados:** `kubelet` e `CRI-O` / `containerd`, permitindo que os managers gerenciem os Static Pods locais e executem workloads se necessário.
  * **SELinux e AppArmor:** no AlmaLinux o SELinux fica em `permissive`; no Debian o AppArmor da imagem fica ligado. A política customizada (`k8s-custom-selinux`) existe, mas está desligada por flag. Para detalhes, consulte a página [SELinux e Kubernetes](./selinux.md).

### Workers (2 nós)

* **Função:** executar os pods e workloads do usuário.
* **Componentes instalados:** `kubelet` e o runtime de contêiner (`CRI-O` por padrão, ou `containerd`), com os plugins CNI, mas sem os serviços de controle (`etcd` e API Server).

> 💡 O cluster não tem `kube-proxy`: o Cilium faz esse papel em eBPF.

### Bastion Host (Kubox)

* **Função:** máquina de gestão que centraliza as operações administrativas.
* **Ferramentas:** `kubectl`, `helm`, `etcdctl`, `yq` e outras utilidades são instaladas via Ansible para permitir a administração e o monitoramento do cluster.
* **Benefícios:** facilita a gestão sem necessidade de acessar diretamente managers ou workers.

## Addons e Serviços Complementares

A estrutura do cluster é enriquecida com diversos addons, instalados via Ansible e detalhados na documentação específica ([Addons e Serviços Complementares](./addons.md)):

* **Plugin de rede (CNI):** `cilium` (eBPF), com Gateway API, LoadBalancer IPAM, anúncio L2 e substituição do `kube-proxy` integrados.
* **CoreDNS:** fornece resolução de nomes interna no cluster, instalado como chart Helm.
* **Metrics Server:** coleta métricas de CPU e memória dos pods/nodes.
* **NFS Subdir External Provisioner:** cria volumes persistentes dinâmicos a partir do servidor NFS.
* **Gateway API (Envoy do Cilium):** permite exposição de aplicações HTTP/HTTPS via objetos Gateway/HTTPRoute, usando a implementação nativa baseada em Envoy do Cilium.
* **Headlamp Dashboard:** oferece uma interface web de administração, instalada com service account apropriada.
* **Vertical Pod Autoscaler (VPA):** analisa o uso de recursos e sugere/ajusta limites de recursos verticalmente para os contêineres dos Pods de forma dinâmica.
* **Stack de Observabilidade (kube-prometheus-stack + Grafana):** coleta e armazena métricas detalhadas dos componentes do cluster (nós, pods, CoreDNS e control plane) no Prometheus e as visualiza em dashboards ricos pré-configurados no Grafana.

## Automação com libvirt, cloud-init, Makefile e definições de rede

Para criar as máquinas virtuais e simplificar a execução dos playbooks, o projeto usa o **libvirt** (KVM), o **cloud-init** e um **Makefile** que expõe comandos úteis. Os detalhes estão em [Provisionamento](./provisionamento.md).

### VMs no libvirt

O playbook `ansible/provisiona.yml` (role `infra-vms`) lê o inventário Ansible ativo (`inventario/hosts.yml`, que é um symlink gerenciado pelo Makefile apontando para uma das configurações em `configs/hosts-*.yml`) e cria as VMs conforme os grupos e hosts definidos. Cada VM recebe:

* **Nome, IP, memória e CPUs** a partir das variáveis `ansible_host`, `memory` e `cpus` do inventário. O domínio se chama `k8sbox-<host>`.
* **Disco** como overlay qcow2 da imagem cloud da distro (`distro_base`), em `.target/vms/<host>/disco.qcow2`.
* **Chave SSH** gerada automaticamente em `.target/cluster/ssh/`, entregue pelo cloud-init ao usuário `k8sbox`.
* **Rede:** uma única placa na rede libvirt `k8sbox_mgmt` (NAT, `172.24.0.0/24`, sem DHCP). O cloud-init casa a placa pelo MAC, a renomeia para `mgmt0` e configura o IP fixo (ex.: `172.24.0.x`), o gateway `172.24.0.1` e os DNS públicos (`1.1.1.1` e `8.8.8.8`). O nome `mgmt0` é o mesmo nas duas distros.

Assim, o cluster opera em uma faixa de IPs **172.24.0.0/24**, definida em `inventario/group_vars/all.yml` como `rede_cidr_hosts`.

### Configurações de Cluster

O projeto oferece duas configurações pré-definidas para diferentes cenários:

- **`configs/hosts-mini.yml`**: configuração padrão balanceada (1 LB, 1 Manager, 2 Workers)
- **`configs/hosts-completo.yml`**: configuração completa (2 LBs, 3 Managers, 2 Workers) para alta disponibilidade

A configuração ativa é controlada via symlink `inventario/hosts.yml` usando os comandos `make init` e `make status`. Consulte o [README principal](../README.md#gerenciamento-de-configurações) para mais detalhes.

### Makefile

O `Makefile` agiliza tarefas recorrentes:

* `make init`: ativa a configuração de cluster definida em `config.mk` (ex: `CLUSTER = mini`)
* `make status`: mostra qual configuração está atualmente ativa
* `make bootstrap`: confere se o host tem o que o projeto precisa (o `make up` já o chama).
* `make k8s-in-a-box`: sobe todo o cluster e grava os logs da execução em `.target/logs/`.
* `make up`: cria e liga as VMs do cluster no libvirt (o `kubox` sobe com `make ops-up`).
* `make ssh-<host>`: abre SSH numa VM (ex.: `make ssh-manager1`).
* `make cluster`: executa o playbook do cluster (`cluster.yml`) com a tag `cluster`, automatizando a instalação completa.
* `make infra` / `make control-plane`: executam só a parte pré-Kubernetes ou só o Kubernetes core.
* `make ops`: aplica o playbook de operações `ops.yml` para configurar a rede (Cilium) e utilitários adicionais no host `kubox`.
* `make exemplos`: aplica o playbook para exemplos de aplicações.
* `make snapshot` / `make restore`: gerencia snapshots das VMs para facilitar restaurações de estado.
* `make clean-k8s`, `make clean-vms`, `make clean-cluster`, `make clean-all` e `make purge`: limpeza em camadas, do Kubernetes até o `.target` inteiro.

### Definições de Rede do Cluster

As redes do cluster são declaradas em `inventario/group_vars/all.yml`:

* **rede_cidr_hosts:** `172.24.0.0/24`, alocada para as VMs (load balancers, managers, workers, NFS e kubox).
* **rede_cidr_pods:** `172.25.0.0/17`, destinada aos pods.
* **rede_cidr_services:** `172.25.128.0/17`, destinada aos serviços ClusterIP.
* **VIP e LoadBalancers:** o VIP do Keepalived é `172.24.0.10`; há duas faixas de IPs de LoadBalancer do Cilium (`lb_ips_fixos`: `172.24.0.101-172.24.0.150` e `lb_ips_dinamicos`: `172.24.0.201-172.24.0.250`).

Essas redes, combinadas com o Cilium e com o load balancer HAProxy, permitem que o cluster opere de forma isolada, com endereços internos previsíveis para hosts, pods e serviços.

# Conclusão

Este documento apresentou uma visão geral da arquitetura do `k8s‑in‑a‑box`, descrevendo os componentes principais do cluster, os addons instalados e a infraestrutura de provisionamento com libvirt, cloud-init, Makefile e as configurações de rede. O objetivo foi mostrar como cada elemento contribui para formar um ambiente Kubernetes completo, replicável e de fácil gestão.

Nas demais páginas desta documentação, são explorados em detalhes o funcionamento e a configuração de cada serviço e addon, incluindo o balanceamento com HAProxy/Keepalived, o provisionamento persistente via NFS, a criação dos nós managers e workers (com seu runtime CRI-O/containerd) e a instalação completa dos addons de cluster.
