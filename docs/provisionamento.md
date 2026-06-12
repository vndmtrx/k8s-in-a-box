# Vagrant, Makefile e Ansible

A orquestração de todo o ciclo de vida do ambiente **k8s-in-a-box** baseia-se numa trindade de ferramentas conhecidas no mercado. Juntas, elas garantem que o "Kubernetes da maneira difícil" seja executado da "maneira mais reproduzível possível".

Esta página aprofunda-se em como essas três engrenagens operam.

## Vagrant e LibVirt

O **Vagrant** é o motor que traduz as intenções do usuário em máquinas virtuais de verdade rodando no hospedeiro.

* **Provider LibVirt (KVM):** Optou-se por focar no provedor `libvirt` em vez do clássico VirtualBox, dados os enormes ganhos de performance e eficiência usando hipervisores nativos no Linux (KVM).
* **Leitura Dinâmica:** Diferentemente de `Vagrantfiles` estáticos longos, o arquivo deste projeto (escrito em Ruby) usa um módulo YAML para abrir e interpretar o arquivo de inventário do Ansible ativo (`inventario/hosts.yml`). Ele varre todos os grupos (`loadbalancers`, `managers`, `workers`, etc.) e itera construindo as VMs com a RAM e CPU declaradas.
* **Múltiplas Placas de Rede:**
  * **eth0 (Rede NAT / LibVirt Padrão):** É usada para acesso à internet durante o processo de download de imagens e pacotes (como `yum install`). Contudo, o projeto propositalmente ignora essa rede para tráfego do cluster interno.
  * **eth1 (Rede Privada 172.24.0.0/24):** Essa é o ponto vital. O Vagrant atribui os IPs estáticos descritos no inventário a essas placas. Todo o tráfego do cluster (`etcd`, `api-server`, pods) transita por aqui, impedindo que peculiaridades da sua rede doméstica (DHCP alterado, firewalls na sua máquina host) quebrem as simulações de roteamento de contêineres.

## Ansible

Onde o Vagrant cria o hardware genérico, o **Ansible** injeta a "alma" no sistema. O provisionamento é puramente declarativo.

* **O Playbook Mestre (`ansible/cluster.yml`):**
  A espinha dorsal que comanda a execução metódica de todas as roles na ordem exata de dependências. Ele executa: geração de certificados (`infra-pki`), base de SO, balanceador, kubelet (iniciado antes do etcd para gerenciar os static pods do control plane), etcd, control plane (como Static Pods) e, por fim, os complementos em `addons.yml`. O `kube-proxy` é aplicado como parte do playbook `ops.yml` via role `addon-kube-proxy` após o cluster estar ativo.
* **Injeção de Variáveis:**
  Todo o comportamento dos playbooks deriva do arquivo universal `inventario/group_vars/all.yml`. Esse padrão permite que o usuário mude versões (ex: de Kubernetes v1.35 para v1.36) e plugins apenas manipulando esse arquivo, não precisando nunca tocar nos códigos subjacentes da pasta `ansible/`.
* **Configuração Personalizada (`.ansible.cfg`):**
  Um arquivo de configuração focado no contexto do projeto. Entre os ajustes vitais, desativa verificações host-key (`host_key_checking = False`) o que é indispensável quando se recria VMs que repetem o mesmo IP estático frequentemente num ambiente temporário.

## Otimizações de Provisionamento

Para otimizar o tempo de provisionamento e mitigar o uso desnecessário de banda de internet, o projeto implementa duas estratégias avançadas:

### 1. Cache Local de Imagens de Containers
As imagens do sistema (Kubernetes, pause, etcd, etc.) são pesadas e seu download repetido a cada nova criação de cluster consome banda e tempo significativos. O projeto resolve isso via cache no host de desenvolvimento:
* **Detecção:** A role `k8s-kubelet` (`tasks/07-download-imagens-sistema.yml`) verifica se os tarballs das imagens necessárias já existem localmente no host na pasta `imagens/` (definida pelas variáveis do projeto).
* **Download Centralizado:** Se ausente, o primeiro manager (`manager1`) faz o download da imagem via `skopeo copy` direto do registro de container para um tarball local e envia o arquivo de volta para o host de desenvolvimento (via `ansible.builtin.fetch`).
* **Distribuição e Carga:** Para cada nó no cluster, o Ansible copia o tarball do host local para a VM e o importa diretamente no runtime de container configurado:
  * No **CRI-O**: A importação ocorre via `skopeo copy` para o `containers-storage`.
  * No **Containerd**: A importação ocorre via `ctr -n k8s.io images import`.
* **Benefício:** Permite um provisionamento rápido ("offline-ready") após o primeiro download.

### 2. Extração Dinâmica do `etcdctl` via OverlayFS
Tradicionalmente, a instalação da ferramenta de gerenciamento do `etcd` (`etcdctl`) exigiria o download do arquivo compactado completo de lançamento do etcd na internet para descompactar apenas um binário. No projeto:
* O Ansible identifica o container ID do etcd em execução no `manager1` usando `crictl ps`.
* Consulta os metadados do container via `crictl inspect` e extrai o caminho do diretório mesclado no OverlayFS (`merged layer`) que contém o sistema de arquivos em tempo de execução do container.
* Copia o executável `etcdctl` diretamente desse caminho do OverlayFS do manager para o host local e depois o instala no bastion host `kubox`.
* **Benefício:** Remove o download do tarball de distribuição do etcd, reduzindo a dependência de APIs externas e acelerando o provisionamento das ferramentas.

## Makefile

Digitar comandos longos de Ansible e Vagrant repetidamente gera atrito e abre espaço para erros de digitação. O **Makefile** age como um "encapsulador de interfaces de comando" fácil.

* **Verificação de dependências (`make check-deps`):**
  * Garante que o host local possua os componentes essenciais (`ansible`, `vagrant`, `libvirt`/`kvm` e o plugin `vagrant-libvirt`) instalados com as permissões corretas antes de iniciar a construção.
* **O Comando `make init`:**
  * Como o sistema de topologias (nano, mini, completo) baseia-se em symlinks, o `make init` apaga links antigos e cria um link fresco apontando para a pasta `/configs`.
* **A Construção Completa (`make k8s-in-a-box`):**
  * Este é um comando meta. Ele roda primeiro a subida de todo o hardware (`make cluster-up` -> invoca vagrant up), em seguida dispara o playbook principal do Ansible com tags de filtro adequadas e, por fim, aplica configurações adicionais no bastião `kubox`.
* **Execuções Focadas (`make cluster-etcd`, `make cluster-kubelet`):**
  * Durante testes locais focados na configuração de apenas um subsistema, essas tags executam apenas as tarefas correspondentes na role designada, poupando a meia hora que a execução completa levaria e viabilizando o "ciclo de estudo rápido".

Através desta simbiose, uma rede inteira virtual com suas complexidades se materializa num computador pessoal com apenas dois comandos.
