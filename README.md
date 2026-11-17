# 🧩 k8s-in-a-box

Kubernetes in a Box, uma instalação manual de um cluster Kubernetes com alta disponibilidade, em VMs que o próprio Ansible cria no libvirt (KVM) a partir das imagens cloud do Debian 13 ou do AlmaLinux 10.

![Kubernetes Dashboard](docs/cluster.png)

> 💡 Construído usando o Kubernetes v1.37.2 ([Kubernetes v1.37 - Garhwal Release Notes](https://kubernetes.io/blog/2026/08/26/kubernetes-v1-37-release/))

Este projeto nasceu como uma evolução natural de outro projeto de estudos ([vndmtrx/vagrant-k8s-cluster](https://github.com/vndmtrx/vagrant-k8s-cluster)), onde o cluster era criado utilizando o `kubeadm`. Durante aquele desenvolvimento, percebi que boa parte das etapas executadas pelo `kubeadm` (como a geração de certificados, configuração do etcd e bootstrap dos componentes do control plane) aconteciam de forma automática, sem que eu realmente compreendesse o que estava acontecendo nos bastidores.

Com isso, o **k8s-in-a-box** surgiu como uma forma de reconstruir esse processo manualmente, etapa por etapa, para entender profundamente como o Kubernetes realmente se forma: dos certificados ao control plane e worker nodes.

Este projeto segue a filosofia *"Kubernetes The Hard Way"* ([kelseyhightower/kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way)), demonstrando cada fase de instalação dos componentes essenciais (`PKI`, `etcd`, `Control Plane` e `Worker Nodes`) sem recorrer a ferramentas de conveniência como `kubeadm` ou `k3s`.

O objetivo é oferecer um laboratório de estudos que permita compreender os fundamentos do Kubernetes em sua forma mais pura, mantendo ainda a automação e reprodutibilidade via Ansible.

> [!IMPORTANT]
> **Aviso Importante / Disclaimer:**  
> Este projeto foi concebido estritamente para **fins de estudo, experimentação e aprendizado detalhado** sobre a construção e o funcionamento interno de cada componente de um cluster Kubernetes. Ele **não** tem o intuito de substituir ferramentas consagradas de montagem rápida e gerenciamento de clusters, como `kubeadm`, `k3s`, `k0s`, `minikube` ou `kind`. O objetivo principal aqui é abrir a "caixa preta" do Kubernetes, permitindo que o estudante interaja manualmente com etapas que costumam ser abstraídas por essas ferramentas.

![libvirt](https://img.shields.io/badge/libvirt-KVM-4E4E9A?logo=qemu&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?logo=ansible&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white)
![AlmaLinux](https://img.shields.io/badge/AlmaLinux-2D4F8C?logo=almalinux&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![etcd](https://img.shields.io/badge/Etcd-419EDA?logo=etcd&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-277A9F?logo=helm&logoColor=white)

## Estado Atual do Projeto

Este projeto está em desenvolvimento ativo, seguindo uma abordagem progressiva de construção do cluster Kubernetes.  

Além da implementação prática do cluster, também está sendo criada uma documentação detalhada sobre cada etapa do processo, explicando as decisões tomadas em cada fase: da escolha de tecnologias e configurações de rede/infraestrutura à instalação dos componentes de controle e nós de trabalho.  

A implementação segue uma sequência lógica que respeita as dependências entre os componentes, garantindo reprodutibilidade e clareza em todo o processo.

### Documentação

Todo o material de referência e guias de instalação encontra‑se no diretório `docs/` do repositório. O índice completo, com links para cada seção, está disponível em [`docs/README.md`](./docs/README.md).

## Visão Geral

O repositório automatiza a criação de várias máquinas virtuais em uma rede privada para as VMs, onde o cluster e as ferramentas anexas são instaladas. Na máquina host, o projeto só cria a rede `k8sbox_mgmt` e os domínios `k8sbox-*` no libvirt; os discos, o cache, as chaves, a PKI e os logs ficam na pasta `.target/`, dentro do repositório.

Com o Ansible como provedor de automação, cada componente do cluster é instalado e configurado explicitamente: geração de certificados, criação do cluster `etcd`, deployment do plano de controle como **Static Pods** gerenciados pelo `kubelet`, instalação do runtime de contêiner e do `kubelet`, além da instalação dos vários plugins de suporte do cluster. A camada de sistema operacional (pacotes, rede, relógio, idioma e atualizações) fica com o **cloud-init**, no primeiro boot de cada VM. O cluster não usa `kube‑proxy`: o Cilium faz esse papel.

### Componentes Concluídos
- Infraestrutura com libvirt/KVM e cloud-init, criada pelo Ansible (playbook `provisiona.yml`)
- Framework de Automação Ansible
- Sistema Base das VMs: Debian 13 (padrão) ou AlmaLinux 10, com UEFI e Secure Boot
- PKI (Certificados para todos componentes)
- Load Balancer (HAProxy)
- Cluster etcd
- Manager nodes (Control Plane)
- Worker Nodes
- Arquivos de Configuração
- Política SELinux customizada (desligada por flag; ver [SELinux](docs/selinux.md))
- Addons de Cluster (Cilium, CoreDNS, Métricas, Gateway API, Dashboard, VPA, Prometheus Stack + Grafana)
- Ferramentas de gerenciamento (etcdctl, kubectl, helm)
- Exemplos de deploys no cluster
- Testes de conformidade com o Sonobuoy

> 💡 Para um acompanhamento detalhado do desenvolvimento, incluindo todos os componentes e suas dependências, consulte o [Mapa de Progresso](docs/progresso.md).

## Decisões de Design

Algumas escolhas foram tomadas para simplificar o laboratório e maximizar o aprendizado:
1. **libvirt + Ansible, sem Vagrant**: o playbook `provisiona.yml` (role `infra-vms`) define a rede e os domínios no libvirt (`qemu:///system`, sem `sudo`), cria cada disco como overlay qcow2 de uma imagem cloud fixada por versão e entrega a configuração da VM pelo cloud-init. O Vagrant saiu do projeto em 2026-11; quem vem da versão antiga deve rodar `vagrant destroy -f` antes do primeiro `make up`, porque as VMs antigas usam os mesmos IPs.
1. **Rede Privada 172.24.0.0/24**: todas as VMs estão em uma rede privada, evitando conflitos com redes domésticas. Os pods e serviços usam redes separadas para manter isolamento.
1. **Alta Disponibilidade**: HAProxy e Keepalived fornecem um VIP (`172.24.0.10`) e fazem balanceamento do etcd e do API Server, permitindo um failover transparente dos endpoints.
1. **Duas distribuições, Debian como padrão**: a variável `distro_base` escolhe entre `debian` (Debian 13, padrão) e `almalinux` (AlmaLinux 10), para o cluster inteiro ou por host; um cluster pode misturar as duas. As diferenças entre as distros ficam numa única tabela, na role `infra-vms` ([Provisionamento](docs/provisionamento.md#diferenças-entre-as-distribuições)). As duas passaram na conformidade; o Debian ficou como padrão porque sobe mais rápido e usa menos memória (ver [Conformidade e Validação](#conformidade-e-validação)).
1. **Certificados Gerenciados**: a geração de uma cadeia PKI completa (Root CA, CAs intermediárias e certificados de cliente e servidor) garante segurança entre todos os componentes, e também foi feita dessa forma para experimentações com rotação de certificados.
1. **Runtime de Conteiners**: o CRI-O é o padrão, e o containerd (com o runc) está disponível para estudo. Os dois vêm como pacote estático, com versão fixada no inventário (`versao_crio`, `versao_containerd`, `versao_runc`), e não dos repositórios da distro; por isso a atualização automática do SO não os atualiza.
1. **Plugin de Rede**: o Cilium (eBPF) é o único CNI do projeto. Ele substitui o kube-proxy, entrega os IPs de LoadBalancer (LB IPAM com anúncio L2), implementa a Gateway API e traz a observabilidade do Hubble. O Canal (Calico + Flannel), com kube-proxy, Kube-vip e Traefik, saiu do projeto em 2026-11 para simplificar a manutenção.
1. **Control Plane via Static Pods**: em vez de instalar os componentes do plano de controle (`etcd`, `kube-apiserver`, `kube-controller-manager` e `kube-scheduler`) como serviços do sistema operacional gerenciados pelo `systemd` (modo tradicional), optou-se pela implantação via **Static Pods**. Isso simplifica o processo ao eliminar a necessidade de criar e gerenciar múltiplos Unit Files do systemd para cada componente, alinhando o projeto com as práticas de instalações modernas do Kubernetes (como o `kubeadm`). 
   * *Nota de Evolução:* Inicialmente, o projeto nasceu de forma puramente *"hard way"*, instalando cada um dos componentes manualmente a nível de sistema operacional (com downloads diretos e unit files manuais). A consolidação para Static Pods, embora ainda preserve o aspecto *"hard way"* (já que toda a cadeia PKI, certificados, arquivos de configuração e parâmetros ainda são gerados manualmente etapa por etapa pelo Ansible), adota uma arquitetura mais moderna, organizada e resiliente (o próprio Kubelet gerencia o ciclo de vida e a saúde dos componentes do control plane locais).
1. **Sem kube-proxy**: o Cilium faz o papel do `kube-proxy` em eBPF (`kubeProxyReplacement`), então o cluster não instala o `kube-proxy`.
1. **SELinux e AppArmor**: no AlmaLinux o SELinux fica em modo `permissive`; no Debian o AppArmor da imagem fica ligado. O projeto tem uma política de Type Enforcement customizada (`k8s-custom-selinux`), mas ela está desligada pela flag `selinux_politica_customizada: false` e fica para uma fase futura. Para detalhes, consulte a [documentação de SELinux](docs/selinux.md).
1. **Cache Local de Imagens com Skopeo**: para evitar downloads repetitivos a cada recriação do cluster, o projeto armazena em cache no host os tarballs das imagens necessárias (via `skopeo copy`). Nas VMs, elas são distribuídas e carregadas diretamente no CRI-O (`containers-storage`) ou Containerd (`ctr`).
1. **Extração do `etcdctl` da imagem do etcd**: em vez de baixar um tarball completo do Etcd da internet para obter o binário cliente no host de operação (`kubox`), o Ansible o extrai da imagem do etcd que já está no cache de imagens do host. O binário tem a mesma versão do container e a extração funciona com CRI-O e com containerd.

## Arquitetura e Configurações de Instalação

Aqui está a base do laboratório: uma topologia mínima funcional e uma topologia de referência. A mínima existe para quem tem menos memória disponível; a de referência é a em uso atualmente e serve de guia para as configurações abaixo.

A personalização do cluster é feita em dois arquivos principais:

- **Configurações de cluster pré-definidas** (`configs/hosts-*.yml`): o projeto oferece duas configurações prontas para diferentes cenários:
  - `configs/hosts-mini.yml` - configuração padrão balanceada (padrão do projeto)
  - `configs/hosts-completo.yml` - configuração completa para estudos avançados e testes de alta disponibilidade
  
  A configuração ativa é controlada via symlink em `inventario/hosts.yml`, controlado pelo `Makefile`. Cada arquivo define as VMs que compõem o cluster, contendo endereço IP, FQDN, memória e CPU para cada host.


* `inventario/group_vars/all.yml` define as variáveis globais do projeto e centraliza as configurações que controlam o comportamento das *roles* do Ansible. É nele que se personaliza a instalação e o funcionamento do cluster.
  Algumas das principais opções que podem ser ajustadas:

  * **Distribuição das VMs:** `distro_base` escolhe entre `debian` (padrão) e `almalinux`; um host pode sobrescrevê-la em `configs/hosts-*.yml`.
  * **Runtime de Conteiner** permite a escolha entre `crio` ou `containerd` para a parte de conteiners.
  * **Atualização automática do SO:** `atualiza_sistema` aceita `nenhum`, `seguranca` (padrão) ou `todos`.
  * **Versões dos componentes:** define quais versões do Kubernetes, etcd, Helm e CNI Plugins serão utilizadas.
  * **Redes do cluster:** configura os blocos de endereçamento das redes de *hosts*, *pods* e *services*.
  * **Faixas de IPs de LoadBalancer:** controla os intervalos que o Cilium entrega aos serviços (IPs fixos e dinâmicos).
  * **Parâmetros de HAProxy e Keepalived:** ajusta timeouts, portas e o IP virtual (VIP) usado para alta disponibilidade.
  * **Certificados e artefatos:** define estrutura de diretórios e se os certificados serão regenerados automaticamente.

> 💡 Juntos, `hosts.yml` e `all.yml` formam o núcleo de personalização do projeto: o primeiro define onde o cluster será executado, e o segundo define como ele será configurado.
> O cluster pode ser expandido ou reduzido conforme a capacidade de memória e processamento disponível, bastando ajustar os parâmetros definidos nos arquivos de inventário.

### Topologia de rede

As VMs ficam em uma **rede privada** (`172.24.0.0/24`) e os **pods/serviços** usam faixas separadas para evitar conflitos:

* **Hosts (VMs):** `172.24.0.0/24`
* **Pods:** `172.25.0.0/17`
* **Serviços:** `172.25.128.0/17`

O ambiente expõe um **VIP** para alta disponibilidade do plano de controle via Keepalived e HAProxy (`172.24.0.10`), mapeado por FQDNs como `api.k8sbox.local` e `etcd.k8sbox.local`.
Para expor serviços via LoadBalancer, há duas faixas pré-definidas para o Cilium (`lb_ips_fixos` e `lb_ips_dinamicos`), que podem ser ajustadas conforme sua rede local.

Inclusive, é possível verificar o status do HAProxy em [http://172.24.0.21:9000/stats](http://172.24.0.21:9000/stats) (usuário/senha: `admin` / `senha_muito_segura!`).

> 💡 A senha da página de status HAProxy é exclusiva para o laboratório. Caso queira mudar, existe uma variável em [inventario/group_vars/all.yml](inventario/group_vars/all.yml) em que você pode alterar essa (e outras) informações.

### Componentes e alta disponibilidade

* **Balanceamento:** HAProxy faz o **failover** e o balanceamento do **kube-apiserver** e do **etcd**.
* **PKI:** toda a comunicação entre componentes é protegida por certificados emitidos pela **cadeia PKI** do projeto (Root CA + CAs intermediários para cada componente core).
* **Runtime:** `crio` como padrão pela simplicidade e estabilidade; `containerd` disponível.
* **CNI:** `cilium` (eBPF), que também substitui o `kube-proxy`.
* **LoadBalancer (Cilium):** o LB IPAM do Cilium entrega os IPs dos serviços `LoadBalancer`, e o anúncio L2 (ARP) os torna alcançáveis na rede de management.
* **Bastion (kubox):** host com `kubectl`, `etcdctl`, `helm` e utilitários para operar e inspecionar o cluster sem “poluir” os nós.

### Ordem de provisionamento (resumo)

O `Makefile` e os playbooks do Ansible conduzem a instalação em etapas, respeitando as dependências:

1. **VMs** (`make up`: rede, discos e domínios no libvirt; o cloud-init instala os pacotes do SO e configura rede, relógio e idioma; depois o snapshot `so`)
2. **Artefatos e PKI** (binários, CAs e certificados)
3. **Sistema Base** (pré-requisitos de SO, tunáveis de rede)
4. **Balanceador** (HAProxy/Keepalived)
5. **kubelet** (runtime de container, plugins CNI e configuração do kubelet)
6. **etcd** (cluster e mTLS)
7. **Control Plane** (API Server, Controller Manager, Scheduler)
8. **Rede** (Cilium com Gateway API, aplicado via `kubox` após o cluster estar funcional)
9. **Addons** (CoreDNS, métricas, dashboard, observabilidade, etc.)

Você pode executar tudo de ponta a ponta com `make k8s-in-a-box` ou chamar **targets**/tags individuais para depurar etapas específicas.

### Customizações rápidas

As principais opções ficam em `inventario/group_vars/all.yml`:

* **Distribuição e runtime:** `distro_base` (`debian` ou `almalinux`) e `container_runtime` (`crio` ou `containerd`)
* **Rede dos hosts/pods/serviços:** `rede_cidr_hosts`, `rede_cidr_pods`, `rede_cidr_services`
* **VIP/HAProxy/Keepalived:** `keepalived_vip_ip`, `vip_api_fqdn`, `vip_etcd_fqdn`, timeouts e credenciais do HAProxy
* **LoadBalancer (Cilium):** `lb_ips_fixos` e `lb_ips_dinamicos`
* **Versões:** `versao_kubernetes`, `versao_etcd`, `versao_cni`, `versao_helm`, `versao_crio`, `versao_containerd`

> 💡 Dica: ajuste primeiro CPU/RAM em `configs/hosts-*.yml`. Em seguida, valide **rede** e **VIP**.

## Início Rápido

1. Instale os pacotes do SO (exemplo para Debian 13). O `make bootstrap`, no passo 4, confere cada um e mostra o comando `apt` ou `dnf` com o que faltar:
```bash
sudo apt install libvirt-daemon-system qemu-system-x86 qemu-utils ovmf cloud-image-utils python3-libvirt pipx
sudo usermod -aG libvirt "$USER"   # depois, saia e entre de novo na sessão
```
O Ansible, o `netaddr` e o `ansible-lint` não vêm do SO: o próprio projeto os instala com o `pipx`, em versões fixas, dentro de `.target/ferramentas` (sem `sudo` e sem mexer em outro Ansible que você tenha). Os alvos do `Makefile` usam essas ferramentas.

2. Clone o repositório:
```bash
git clone https://github.com/vndmtrx/k8s-in-a-box.git
cd k8s-in-a-box
```

3. (Opcional) Defina a configuração do cluster no arquivo `config.mk` na raiz do projeto (crie o arquivo se não existir):
```makefile
CLUSTER = mini # Opções: mini, completo
```
E então ative-a rodando:
```bash
make init
```

4. Verifique a configuração ativa e os pré-requisitos do host:
```bash
make status
make bootstrap
```

5. Faça o provisionamento da estrutura completa:
```bash
make k8s-in-a-box
```

> 💡 Se você não executar `make init`, o projeto usará automaticamente a configuração `mini` como padrão.

> ⚠️ Quem vem da versão com Vagrant deve rodar `vagrant destroy -f` (e, se quiser, `vagrant box remove`) na versão antiga antes do primeiro `make up`: as VMs antigas usam os mesmos IPs da rede `172.24.0.0/24`.

## Gerenciamento de Configurações

O projeto utiliza um sistema de configurações baseado em symlinks para facilitar a alternância entre diferentes topologias de cluster.

### Comandos disponíveis

- **Validar o host:** `make bootstrap`. Ele confere os pacotes do SO e mostra o comando que instala os que faltam; depois instala as ferramentas do projeto (`make ferramentas`) e confere a collection `community.libvirt`, o grupo `libvirt`, o `/dev/kvm`, o acesso do QEMU à pasta `.target/` e a RAM e o disco livres para a topologia. O `make up` roda o `bootstrap` antes de criar as VMs.
- **Ferramentas do projeto:** `make ferramentas` instala (ou confere) o Ansible, o `netaddr` e o `ansible-lint` em `.target/ferramentas`, nas versões `VERSAO_ANSIBLE`, `VERSAO_ANSIBLE_CORE`, `VERSAO_NETADDR` e `VERSAO_ANSIBLE_LINT` do `Makefile`. Para usá-las fora do `make`: `export PATH="$PWD/.target/ferramentas/bin:$PATH"`.
- **Ativar uma configuração:** `make init` (carrega e ativa o tipo configurado em `config.mk`)
- **Ver configuração ativa:** `make status`
- **Ajuda completa:** `make help`

### Configurações disponíveis

| Configuração | Load Balancers | Manager Nodes | Worker Nodes | Total | Recursos |
|--------------|----------------|---------------|--------------|---------------|----------|
| `mini` | 1 | 1 | 2 | 3 nós | ~12GB RAM, 9 vCPUs |
| `completo` | 2 | 3 | 2 | 5 nós | ~21GB RAM, 18 vCPUs |

> 📝 **Nota:** O total de nós considera apenas managers + workers. Já os recursos incluem todas as VMs (LBs, NFS, cluster e kubox).

> 💡 As configurações específicas de cada topologia estão em `configs/hosts-*.yml`. Você pode criar suas próprias configurações personalizadas seguindo o mesmo padrão.

## Acessando as VMs

Use o comando abaixo para acessar individualmente cada máquina virtual do projeto (o nome é o do inventário, como `manager1` ou `kubox`):
```bash
make ssh-<nome da VM>
```

O usuário das VMs é `k8sbox`, com a chave SSH do cluster em `.target/cluster/ssh/id_ed25519` (configurada em `ssh_config`).

## Rede

Todas as máquinas estão em uma rede privada (`172.24.0.0/24`), sendo as importantes para o acesso ao cluster as seguintes:
- IP Flutuante do balanceador: `172.24.0.10`
- IP do Bastion Host: `172.24.0.254`

## Operação do Cluster

Para a operação do cluster (e melhor simulação de um ambiente real), as ferramentas de interação com o `etcd` e o cluster foram instaladas em um outro host, chamado `kubox`. O `kubox` não sobe no `make up`; quem o cria é o `make ops-up` (chamado pela esteira). Caso queira verificar o cluster, seguem alguns comandos úteis (para acessar o bastion host, use `make ssh-kubox`):
- `etcdctl`
  - Lista de Membros do cluster: `etcdctl member list -w json | yq -P | tspin`
  - Saúde dos endpoints: `etcdctl endpoint health -w json | yq -P | tspin`
  - Status do cluster: `etcdctl endpoint status -w json | yq -P | tspin`
  - Status do Raft: `etcdctl endpoint hashkv -w json | yq -P | tspin`
- `kubectl`
  - Listar todos os nós: `kubectl get nodes -o wide`
  - Listar todos os pods: `kubectl get pods -A -o wide`
  - Últimos eventos do cluster: `kubectl get events -A --sort-by=.metadata.creationTimestamp`
- `k9s`
  - Interface interativa completa: `k9s`
  - Visualizar pods de um namespace específico: `k9s -n exemplos`
  - Modo readonly (somente leitura): `k9s --readonly`
- `popeye`
  - Análise completa do cluster: `popeye -A`
  - Análise de namespace específico: `popeye -n exemplos`
  - Relatório em formato JSON: `popeye -o json`

## Testes de conformidade (Sonobuoy)

O [Sonobuoy](https://sonobuoy.io/) roda, a partir do `kubox`, os testes de conformidade do próprio Kubernetes (imagem `registry.k8s.io/conformance` da versão do cluster). O modo fica em `sonobuoy_modo`, em cada `configs/hosts-*.yml`:

| Topologia | `sonobuoy_modo` | O que roda | Tempo |
|---|---|---|---|
| `mini` | `quick` | 1 teste (cria e remove um pod) | minutos |
| `completo` | `certified-conformance` | todos os testes `[Conformance]` | horas |

- `make conformidade`: roda o teste no cluster que já está no ar.
- `make teste-conformidade`: remove as VMs, cria o cluster do zero, roda o teste e remove as VMs de novo. O cache e os logs ficam.

O resultado vai para `.target/logs/<execução>/conformidade/`: `resultado.tar.gz` (tudo o que o Sonobuoy coletou), `resumo.txt`, `status.json` e `e2e-falhas.jsonl`. O alvo falha se algum plugin não passar.


## Acesso aos Dashboards (Headlamp, Hubble e Grafana)

No cluster, vários painéis visuais foram ativados para facilitar a administração, monitoramento e visualização dos componentes do cluster.

### 1. Headlamp Dashboard
Para acessar o Headlamp Dashboard, acesse a URL [http://172.24.0.101](http://172.24.0.101/). Quando for solicitado o token de autenticação, gere-o executando o seguinte comando no host `kubox`:
```bash
kubectl -n headlamp create token headlamp-admin
```

### 2. Hubble UI (Observabilidade de Rede)
O **Hubble UI** fornece visualização gráfica detalhada de fluxos de rede, conexões de serviços e políticas aplicadas em tempo real.
* 🌐 **URL de Acesso:** [http://172.24.0.104](http://172.24.0.104/) (sem necessidade de autenticação).

### 3. Grafana (Stack de Observabilidade)
Para visualizar métricas detalhadas do cluster (nós, pods, plano de controle e CoreDNS), acesse o Grafana na URL [http://172.24.0.103](http://172.24.0.103/).
* **Usuário padrão:** `admin`
* **Comando para obter a senha:** Execute o comando abaixo no host `kubox` para obter a senha gerada aleatoriamente:
  ```bash
  kubectl get secret -n monitoramento prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
  ```

### Acesso Remoto (Túnel SSH / Port Forwarding)

Se o seu ambiente `k8s-in-a-box` estiver sendo executado em uma máquina ou servidor remoto (onde você se conecta apenas via SSH), os IPs de LoadBalancer da rede privada (`172.24.0.101`, `172.24.0.103` e `172.24.0.104`) não estarão acessíveis diretamente pelo seu navegador físico local. 

Para resolver isso de forma elegante, você pode criar túneis SSH (**Local Port Forwarding**) para mapear as portas locais do seu computador físico para as IPs virtuais internas do servidor:

#### Método 1: Via Linha de Comando (Linux, macOS ou Windows Terminal)
Execute o comando abaixo no terminal da sua máquina física local para iniciar uma sessão SSH contendo os túneis:
```bash
ssh -L 8080:172.24.0.101:80 -L 8082:172.24.0.103:80 -L 8083:172.24.0.104:80 seu_usuario@ip_do_servidor_remoto
```

#### Método 2: Via PuTTY (Windows GUI)
Se você utiliza o PuTTY para gerenciar suas conexões:
1. Abra o PuTTY e selecione sua sessão salva.
2. No menu lateral esquerdo, vá em: **Connection** -> **SSH** -> **Tunnels**.
3. Adicione o túnel do **Headlamp**:
   * **Source port:** `8080`
   * **Destination:** `172.24.0.101:80`
   * Clique em **Add**.
4. Adicione o túnel do **Grafana**:
   * **Source port:** `8082`
   * **Destination:** `172.24.0.103:80`
   * Clique em **Add**.
5. Adicione o túnel do **Hubble UI**:
   * **Source port:** `8083`
   * **Destination:** `172.24.0.104:80`
   * Clique em **Add**.
6. Volte para a categoria **Session** no topo esquerdo, clique em **Save** para fixar a configuração e clique em **Open** para iniciar a conexão.

Após conectar-se por qualquer um dos métodos, as interfaces estarão acessíveis no seu navegador local nos seguintes endereços:
* 🌐 **Headlamp Dashboard:** [http://localhost:8080](http://localhost:8080)
* 🌐 **Grafana Dashboard:** [http://localhost:8082](http://localhost:8082)
* 🌐 **Hubble UI Dashboard (Cilium):** [http://localhost:8083](http://localhost:8083)

> ⚠️ **ALERTA: É extremamente importante esclarecer que esses dashboards estão sendo expostos através de um Service do tipo LoadBalancer única e exclusivamente para fins de estudo e avaliação do cluster. Em produção, jamais deve-se expor esses componentes à rede pública; caso seja necessário acesso, utilize os mecanismos seguros que o Kubernetes oferece, como o `kubectl proxy` ou `kubectl port-forward`, garantindo que o tráfego permaneça interno ao cluster e protegido por autenticação e controle de permissões.**

## A pasta `.target/`

Tudo o que o projeto gera fica em `.target/`, na raiz do repositório (ignorada pelo git). Ela é do usuário, então apagar qualquer parte dela não exige `sudo`.

```
.target/
├── cache/        # imagens base qcow2, binários e tar das imagens OCI do cluster
├── cluster/      # chave SSH (ssh/) e PKI (pki/) deste cluster
├── ferramentas/  # Ansible, netaddr e ansible-lint do projeto (pipx); bin/ entra no PATH do make
├── vms/<host>/   # disco.qcow2 (overlay), seed.iso, nvram.fd, console.log, cloud-init/
├── ansible/      # ansible.log, cache de fatos e sockets SSH
└── logs/         # uma pasta por execução do make k8s-in-a-box
```

### Logs por execução

`make k8s-in-a-box` roda as etapas `up`, `cluster`, `ops`, `addons` e `exemplos` por meio de `scripts/execucao.py` e grava tudo em `.target/logs/AAAAMMDDhhmmss/`:

| Arquivo | Conteúdo |
|---|---|
| `acoes.log` | saída completa das etapas (make e Ansible, com o tempo de cada tarefa) |
| `etapas.tsv` | etapa, início, fim, duração e código de saída |
| `tarefas/` | um XML JUnit por playbook, com o tempo de cada tarefa |
| `recursos.tsv` | CPU, RAM, swap, disco livre e rede do host, a cada 5 s |
| `maquina.txt` | host, versões, commit, topologia, `distro_base`, runtime e estado do cache |
| `resumo.txt` | duração por etapa, total, bytes baixados, pico de RAM e CPU média |

`make build` roda as mesmas etapas sem gravar logs. Cada VM guarda ainda o console serial (kernel e cloud-init) em `.target/vms/<host>/console.log`, útil quando o SSH não responde.

## Destruindo o ambiente

A limpeza é feita em camadas. Cada alvo apaga também o que os de cima apagam:

| Alvo | O que apaga | A próxima subida |
|---|---|---|
| `make down` | nada: só desliga as VMs | religa as mesmas VMs |
| `make clean-k8s` | o Kubernetes: cada VM volta ao snapshot `so` (SO pronto) | reinstala só o Kubernetes |
| `make clean-vms` | as VMs e `.target/vms` | recria as VMs (o cloud-init baixa os pacotes do SO) |
| `make clean-cluster` | + a rede `k8sbox_mgmt`, a chave SSH, a PKI e `.target/ansible` | + gera chave e PKI novas |
| `make clean-all` | + o cache (imagens base, binários e imagens OCI) | baixa tudo de novo |
| `make purge` | + os logs e as ferramentas: o `.target` inteiro | recomeça do zero (o `bootstrap` reinstala as ferramentas) |

> ⚠️ `clean-all` e `purge` apagam o cache (~2 GiB para baixar de novo), e o `purge` apaga também os logs das execuções anteriores.

Fora do `.target`, o libvirt deixa dois arquivos por VM que só o `sudo` remove: `/var/log/libvirt/qemu/k8sbox-<host>.log` e `/etc/apparmor.d/libvirt/libvirt-<uuid>` (em hosts com AppArmor). Eles não atrapalham uma nova subida.

## Notas Importantes

- A chave SSH do cluster (`.target/cluster/ssh/id_ed25519`) é gerada pelo próprio projeto e serve apenas para o laboratório
- **NÃO USE** esta chave em ambiente de produção
- Para produção, sempre gere e use suas próprias chaves SSH
- O `Makefile` do projeto utiliza uma configuração específica do Ansible localizada em `./ansible/.ansible.cfg`
- **Requisitos de Disco:** o cache ocupa cerca de 2 GiB (as duas imagens base, binários e imagens OCI). Os discos das VMs são overlays qcow2 que crescem com o uso: nas medições de 2026-11-14, uma subida da `mini` ocupou de 12 a 14 GiB, uma da `completo` de 14 a 19 GiB, e a `completo` com a conformidade completa cerca de 25 GiB. Reserve ao menos 30 GiB livres para a `completo`. O `make bootstrap` é mais exigente: ele soma o tamanho máximo de todos os discos (`disk_size` de cada host) e falha se o disco livre for menor que essa soma, mesmo que o uso real seja bem menor
- **Atualizações:** o cloud-init liga a atualização automática do SO (só correções de segurança, por padrão). Ela não atualiza o runtime de contêineres, que vem como pacote estático: para subir a versão, mude `versao_crio` ou `versao_containerd` e recrie o cluster

## Conformidade e Validação

Como parte do estudo, o cluster foi também submetido ao teste de conformidade oficial do Kubernetes, utilizando a ferramenta `sonobuoy` (ver [Testes de conformidade](#testes-de-conformidade-sonobuoy)).  
Esse teste é o mesmo utilizado para validar distribuições Kubernetes certificadas, verificando a compatibilidade e o comportamento esperado dos componentes centrais do sistema.

Em 2026-11-14, com Kubernetes `v1.37.2`, CRI-O e Cilium sem `kube-proxy`, a topologia `completo` passou no modo `certified-conformance` nas duas distribuições:

| Distro | Testes `e2e` | Falhas | Nós | Pods | Esteira inteira | Só a conformidade |
|---|---|---|---|---|---|---|
| Debian 13 | 469 | 0 | 5/5 | 63/63 | 2h29 | 2h08 |
| AlmaLinux 10 | 469 | 0 | 5/5 | 63/63 | 2h52 | 2h12 |

Os demais testes da suíte (2744) ficam como `Skipped` porque não fazem parte da conformidade. O resultado não é uma certificação oficial: ele vale para a topologia, a distro e o runtime testados, e não foi enviado à CNCF.

Esse resultado representa o esforço de automação construído com **Ansible**, **libvirt** e **cloud-init**, que permite não apenas reproduzir o ambiente de forma consistente, mas também estudar e compreender cada etapa da formação de um cluster Kubernetes completo e funcional.

## Nota Pessoal

Este repositório é resultado de um estudo contínuo sobre como montar um cluster Kubernetes manualmente. Ele não é recomendado para uso em produção, apesar de ser bastante resiliente.

Este projeto não é apenas uma implementação, mas um caminho de estudo estruturado para compreender cada aspecto do funcionamento do Kubernetes.

Sinta‑se à vontade para contribuir com sugestões, issues e pull requests.

## Referências e Softwares de Terceiros

Este projeto não implementa novas tecnologias de contêiner ou protocolos de rede proprietários; ele atua puramente como automação e arquitetura de referência. Agradecemos e referenciamos os projetos open-source fundamentais que compõem este ecossistema sob suas respectivas licenças:

* **Kubernetes, etcd, CRI-O e Helm:** Licença Apache 2.0
* **Cilium:** Licença Apache 2.0
* **HAProxy:** Licença GPLv2 / LGPLv2.1
* **Keepalived:** Licença GPLv2
* **Libvirt e KVM:** Licença LGPL / GPLv2
* **QEMU:** Licença GPLv2
* **cloud-init:** Licença Apache 2.0 / GPLv3
* **Debian e AlmaLinux:** imagens cloud oficiais, sob as licenças de cada pacote

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE) - veja o arquivo LICENSE para detalhes.

---

⚠️ **Projeto em desenvolvimento**
