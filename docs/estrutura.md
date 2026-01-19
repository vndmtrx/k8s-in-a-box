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
* **Configuração:** utiliza `nfs-utils` para exportar o diretório `/srv/nfs/k8s`, configurado via template `/etc/exports`; o serviço `nfs-server` é mantido ativo.

### Managers (3 nós)

* **Função:** compõem o control plane do Kubernetes e mantêm o banco de dados do cluster.
* **Componentes instalados:**

  * **Etcd**: banco de dados distribuído, com certificados configurados para mTLS.
  * **Componentes do Control Node:** `kube‑apiserver`, `kube‑controller‑manager` e `kube‑scheduler`, instalados como serviços systemd com seus respectivos certificados e kubeconfigs.
  * **Componentes extras instalados:** `kubelet`, `containerd` e `kube‑proxy`, permitindo que managers também executem workloads se necessário.

### Workers (2 nós)

* **Função:** executar os pods e workloads do usuário.
* **Componentes instalados:** `kubelet`, `containerd` e `kube‑proxy`, com configuração de CNI e plugins instalados, mas sem os serviços de controle (`etcd` e API Server).

### Bastion Host (Kubox)

* **Função:** máquina de gestão que centraliza as operações administrativas.
* **Ferramentas:** `kubectl`, `helm`, `etcdctl`, `yq` e outras utilidades são instaladas via Ansible para permitir a administração e o monitoramento do cluster.
* **Benefícios:** facilita a gestão sem necessidade de acessar diretamente managers ou workers.

## Addons e Serviços Complementares

A estrutura do cluster é enriquecida com diversos addons, instalados superficialmente via Ansible e que serão detalhados em páginas futuras:

* **Plugins de rede (CNI):** escolha entre `flannel` via Helm ou `canal` (Calico + Flannel), cujo manifesto é baixado e ajustado para a faixa de pods.
* **CoreDNS:** fornece resolução de nomes interna no cluster, instalado como chart Helm.
* **Metrics Server:** coleta métricas de CPU e memória dos pods/nodes.
* **NFS Subdir External Provisioner:** cria volumes persistentes dinâmicos a partir do servidor NFS.
* **MetalLB:** implementa balanceamento de serviços em camada 2, atribuindo IPs externos para serviços tipo LoadBalancer.
* **Gateway API (Traefik):** permite exposição de aplicações HTTP/HTTPS via objetos Gateway/HTTPRoute.
* **Headlamp Dashboard:** oferece uma interface web de administração, instalada com service account apropriada.

## Automação com Vagrant, Makefile e definições de rede

Para orquestrar as máquinas virtuais e simplificar a execução dos playbooks, o projeto utiliza **Vagrant** com provider **LibVirt** e um **Makefile** que expõe comandos úteis.

### Vagrantfile

O `Vagrantfile` lê o inventário Ansible ativo (`inventario/hosts.yml`, que é um symlink gerenciado pelo Makefile apontando para uma das configurações em `configs/hosts-*.yml`) e cria as VMs conforme os grupos e hosts definidos. Cada VM recebe:

* **Nome, IP, memória e CPUs** a partir das variáveis `ansible_host`, `memory` e `cpus` do inventário.
* **Chave SSH** gerada automaticamente, adicionada ao `authorized_keys` dos usuários vagrant.
* **Provisionamento de Rede**
    * **Rede LibVirt:** o provider define um rede de gerenciamento (192.168.250.0/24) e cria uma rede privada `k8sbox_mgmt` em modo NAT para os IPs do cluster.
        * `eth0` (rede padrão do Vagrant) tem a rota padrão desativada.
    * **Rede privada:** rede de acesso do cluster à internet e de acesso aos serviços do cluster, pelo usuário do host:
        * `eth1` é configurada como `net_mgmt`, com IP fixo (ex.: `172.24.0.x`), gateway `172.24.0.1` e DNS públicos (`1.1.1.1,8.8.8.8`). O script de provisionamento usa `nmcli` para garantir que essa interface seja persistente.

Assim, o cluster opera em uma faixa de IPs **172.24.0.0/24**, definida em `inventario/group_vars/all.yml` como `rede_cidr_hosts`.

### Configurações de Cluster

O projeto oferece três configurações pré-definidas para diferentes cenários:

- **`configs/hosts-nano.yml`**: configuração mínima (1 LB, 1 Manager, 1 Worker) para ambientes com recursos limitados
- **`configs/hosts-mini.yml`**: configuração padrão balanceada (1 LB, 1 Manager, 2 Workers)
- **`configs/hosts-completo.yml`**: configuração completa (2 LBs, 3 Managers, 2 Workers) para alta disponibilidade

A configuração ativa é controlada via symlink `inventario/hosts.yml` usando os comandos `make init` e `make status`. Consulte o [README principal](../README.md#gerenciamento-de-configurações) para mais detalhes.

### Makefile

O `Makefile` agiliza tarefas recorrentes:

* `make init`: ativa uma configuração específica de cluster (ex: `CLUSTER=nano make init`)
* `make status`: mostra qual configuração está atualmente ativa
* `make k8s-in-a-box`: sobe todo o cluster (executa os dois playbooks completos).
* `make cluster-up`: sobe todas as VMs via Vagrant.
* `make cluster`: executa o playbook `cluster.yml` com a tag `cluster`, automatizando a instalação completa.
* `make cluster-<role>`: executa apenas uma role específica (ex.: `cluster-etcd`, `cluster-kubelet`, etc.).
* `make ops`: sobe a VM `kubox` e aplica `ops.yml` com suas roles (`ops-sistema`, `ops-ferramentas`, `ops-addons`).
* `make exemplos`: aplica o playbook para exemplos de aplicações.
* `make snapshot` / `make restore`: gerencia snapshots das VMs para facilitar restaurações de estado.
* `make clean`: destrói as VMs e remove artefatos gerados.

### Definições de Rede do Cluster

As redes do cluster são declaradas em `inventario/group_vars/all.yml`:

* **rede_cidr_hosts:** `172.24.0.0/24` – alocada para as VMs (load balancers, managers, workers, NFS e kubox).
* **rede_cidr_pods:** `172.25.0.0/17` – destinada aos pods.
* **rede_cidr_services:** `172.25.128.0/17` – destinada aos serviços ClusterIP.
* **VIPs e MetalLB:** o VIP do Keepalived é `172.24.0.10`; há duas faixas de IPs para o MetalLB (`172.24.0.101-172.24.0.150` e `172.24.0.201-172.24.0.250`).

Essas redes, combinadas com a configuração de CNI (Flannel ou Canal) e com o load balancer HAProxy, permitem que o cluster opere de forma isolada, com endereços internos previsíveis para hosts, pods e serviços.

# Conclusão

Este documento apresentou uma visão geral da arquitetura do `k8s‑in‑a‑box`, descrevendo os componentes principais do cluster, os addons instalados e a infraestrutura de provisionamento com Vagrant, Makefile e as configurações de rede. O objetivo foi mostrar como cada elemento contribui para formar um ambiente Kubernetes completo, replicável e de fácil gestão.

Nos próximos textos desta wiki serão explorados em detalhes o funcionamento de cada serviço e addon, incluindo a configuração do HAProxy/Keepalived, o provisionamento NFS, a criação dos nós managers e workers, a função do bastion host e a instalação dos principais addons do cluster.