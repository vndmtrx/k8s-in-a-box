# Plano de Controle e Nós de Trabalho

A verdadeira essência do **k8s-in-a-box** reside na instalação artesanal do plano de controle (Control Plane / Managers) e dos nós de trabalho (Worker Nodes). O projeto não utiliza facilitadores como o `kubeadm`, instalando cada binário como um serviço gerenciado do Linux (`systemd`).

## Preparação Base (Todos os Nós)

Antes de receberem componentes Kubernetes, todos os nós do cluster (Managers e Workers) recebem configurações essenciais aplicadas pela role `05-cluster-base`:

* **Kernel e Rede:** Ajustes de sysctl, em especial a habilitação de roteamento de pacotes (`net.ipv4.ip_forward = 1`) e configurações no iptables para permitir o tráfego em bridge, vitais para os plugins de rede do K8s (CNI).
* **Módulos:** Carregamento de módulos do kernel obrigatórios, como o `br_netfilter` e o `overlay`.
* **Pacotes:** Instalação de utilitários como `curl`, `wget`, `conntrack` e `socat`, requeridos pelo Kubernetes.

## O Cluster Etcd

O **etcd** é o banco de dados chave-valor distribuído que armazena todo o estado do cluster Kubernetes. Sua instalação é tratada pela role `07-etcd`.

* **Certificados (mTLS):** A comunicação do etcd é fortemente protegida. Foram criados certificados específicos para ele no passo de PKI (`01-pki`), validando a identidade de cada nó e encriptando a comunicação do cluster e das respostas aos clientes (API Server).
* **Quorum:** Na configuração `completo`, 3 instâncias do etcd sobem em máquinas diferentes (os managers). O Ansible configura dinamicamente a flag `--initial-cluster` com os IPs de todos os nós para que eles se descubram e formem um quorum válido.
* **Execução:** O binário do etcd é baixado, instalado em `/usr/local/bin` e gerenciado por um arquivo unitário do systemd criado pelo Ansible.

## O Plano de Controle (Managers)

O "cérebro" do cluster é composto por três serviços instalados nos nós Managers. Eles operam de forma interdependente:

1. **kube-apiserver (role `08-kube-apiserver`):**
   * É o único componente que conversa diretamente com o `etcd`.
   * Recebe requisições HTTP (porta 6443), autentica e autoriza o acesso baseando-se nos certificados PKI e tokens, e expõe a API do Kubernetes.
   * Suas flags de configuração são extensas, definindo o IP no qual ele escuta as requisições (no caso, o endereço local do Manager na rede do cluster) e apontando para toda a cascata de certificados de segurança.

2. **kube-controller-manager (role `09-kube-controller-manager`):**
   * Roda em segundo plano avaliando o "estado atual" vs "estado desejado" dos objetos (ReplicaSets, Deployments, Nodes, etc.).
   * Ele utiliza um arquivo `kubeconfig` gerado anteriormente para se autenticar contra o `kube-apiserver`.

3. **kube-scheduler (role `10-kube-scheduler`):**
   * Observa os Pods que acabaram de ser criados e que não têm um nó assinalado.
   * Baseado nas restrições de recursos e labels, ele determina o melhor Worker Node para alocar o Pod.
   * Também consome seu próprio `kubeconfig` para se autenticar.

> 💡 Em um cenário de Alta Disponibilidade (`completo`), todos os Managers rodam esses serviços ao mesmo tempo. O `etcd` e o `kube-apiserver` operam em modo ativo-ativo (balanceados pelo HAProxy), enquanto o `controller-manager` e o `scheduler` operam em eleição de líder (ativo-passivo).

## Nós de Trabalho e Runtime (Workers e Managers)

Após ter o cérebro rodando, é hora de instanciar os "músculos". Embora os Managers controlem o cluster, os pods efetivamente rodam num *Runtime de Contêiner* sob o comando do `kubelet`. No *k8s-in-a-box*, por padrão, os próprios Managers também recebem a função de Workers (embora possam ser "taintados" para não rodar cargas pesadas).

1. **kubelet (role `06-kubelet`):**
   * O "agente" do Kubernetes. Ele lê os manifestos assinalados pelo scheduler e garante que os contêineres definidos neles estejam executando corretamente e de forma saudável.
   * **Runtime:** A variável global `runtime_conteiner` define quem fará o peso pesado. Por padrão, o projeto instala e configura o **CRI-O**. Alternativamente, o **containerd** também está disponível para testes. Ambos implementam a interface CRI do Kubernetes.
   * **SELinux:** A role do kubelet também é responsável por compilar e carregar a política customizada de SELinux (`k8s-custom-selinux`) em cada nó do cluster. O binário do kubelet é instalado com o rótulo `bin_t` e executa sob o contexto `unconfined_service_t` do SELinux. Para detalhes completos, consulte a página [SELinux e Kubernetes](./selinux.md).
   * O Kubelet também usa certificados para se autenticar no API Server. Na inicialização do nó, se a PKI já estiver distribuída, ele sobe; em ambientes onde os certificados não foram pré-gerados (que o k8s-in-a-box simula), ele usa uma técnica de autorização para requisitar um certificado dinamicamente (`kubelet-bootstrap`).

2. **kube-proxy (role `11-kube-proxy-pod`):**
   * Agora roda em cada nó do cluster como um DaemonSet (Pod) em cima do cluster (e não mais como um serviço de sistema systemd local), mantendo regras de rede (através do iptables ou IPVS).
   * É ele quem permite as abstrações de **Services** funcionarem, redirecionando o tráfego do IP do cluster (VIP do Service) para os IPs reais dos Pods executando o contêiner por trás dele.

Concluída a instalação e ativação do `kubelet`, os nós informam seu status para o API Server e passam a constar no comando `kubectl get nodes` como estado `NotReady`. Eles só transitarão para `Ready` na próxima etapa: a instalação dos Addons de Rede (CNI). Somente após o cluster estar ativo é que o `kube-proxy` é provisionado (como DaemonSet) junto com os demais addons, a partir do bastion host `kubox`.
