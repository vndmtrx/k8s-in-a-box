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

* **O Playbook Mestre (`ansible/cluster-$(INSTALACAO).yml`):**
  A espinha dorsal que comanda a execução metódica de todas as roles na ordem exata de dependências (carregando `cluster-bin.yml` para instalação binária ou `cluster-pod.yml` no futuro). Ele executa: geração de certificados (`01-pki`), base de SO, balanceador, kubelet (iniciado antes do etcd para gerenciar os static pods do control plane), etcd, control plane e, por fim, os complementos. O `kube-proxy` é aplicado separadamente, via `ansible/ops.yml`, a partir da máquina `kubox`, após o cluster estar ativo e pronto para receber workloads.
* **Injeção de Variáveis:**
  Todo o comportamento dos playbooks deriva do arquivo universal `inventario/group_vars/all.yml`. Esse padrão permite que o usuário mude versões (ex: de Kubernetes v1.35 para v1.36) e plugins apenas manipulando esse arquivo, não precisando nunca tocar nos códigos subjacentes da pasta `ansible/`.
* **Configuração Personalizada (`.ansible.cfg`):**
  Um arquivo de configuração focado no contexto do projeto. Entre os ajustes vitais, desativa verificações host-key (`host_key_checking = False`) o que é indispensável quando se recria VMs que repetem o mesmo IP estático frequentemente num ambiente temporário.

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
