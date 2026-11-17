# Plano de Controle e Nós de Trabalho

A verdadeira essência do **k8s-in-a-box** reside na instalação artesanal do plano de controle (Control Plane / Managers) e dos nós de trabalho (Worker Nodes). O projeto provisiona os componentes centrais do control plane no modo de **Static Pods** gerenciados pelo `kubelet` a partir de manifestos em `/opt/k8s-in-a-box/manifests`, simulando de forma artesanal o fluxo de inicialização moderno executado pelo `kubeadm`.

---

## Onde ficam os arquivos (`/opt/k8s-in-a-box`)

Tudo o que é do Kubernetes num nó mora em `/opt/k8s-in-a-box`, sem link. Os dados ficam em `/var`, e os daemons do SO e o runtime ficam no lugar padrão.

| Pasta | Conteúdo |
|---|---|
| `/opt/k8s-in-a-box/bin/` | `kubelet` e `crictl` (no PATH dos shells de login por `/etc/profile.d/k8s-in-a-box.sh`; com `sudo`, use o caminho inteiro) |
| `/opt/k8s-in-a-box/manifests/` | manifestos dos Static Pods (`staticPodPath` do kubelet) |
| `/opt/k8s-in-a-box/conf/<componente>/` | configuração e PKI de `etcd`, `kube-apiserver`, `kube-controller-manager` e `kube-scheduler`, montadas nos pods por `hostPath` |
| `/opt/k8s-in-a-box/pki/` | CAs do cluster |
| `/opt/k8s-in-a-box/kubelet/` | `kubelet-config.yml`, `kubelet.kubeconfig`, `kubelet.env` e `pki/` do kubelet |
| `/opt/k8s-in-a-box/so/` | links para as configs dos daemons do SO: `kubelet.service`, `haproxy.cfg`, `keepalived.conf`, `exports`, sysctl, módulos, CRI-O, containerd, `crictl.yaml` e `/etc/cni/net.d` (só os que existem na VM) |
| `/var/lib/etcd`, `/var/lib/kubelet` | dados do etcd e dos pods |

Ficam no lugar padrão: o runtime (`/usr/local/bin/crio`, `/usr/libexec/crio`, `/usr/local/bin/containerd`, `/etc/crio`, `/etc/containerd`), o CNI (`/opt/cni/bin`, `/etc/cni/net.d`, que o Cilium grava) e as ferramentas do `kubox` (`/usr/local/bin`). As pastas montadas em pods (`conf/<componente>/`) não têm link dentro, porque o contêiner não enxerga o destino.

---

## Preparação Base (Todos os Nós)

Antes de receberem componentes Kubernetes, todos os nós do cluster (Managers e Workers) recebem configurações essenciais aplicadas pela role `k8s-cluster-base`:

* **Kernel e Rede:** Ajustes de sysctl, em especial a habilitação de roteamento de pacotes (`net.ipv4.ip_forward = 1`) e configurações no iptables para permitir o tráfego em bridge, vitais para os plugins de rede do K8s (CNI).
* **Módulos:** Carregamento de módulos do kernel obrigatórios, como o `br_netfilter` e o `overlay`.
* **Pacotes:** utilitários como `conntrack`, `socat`, `nftables`, `iptables` e `skopeo` vêm do cloud-init, no primeiro boot da VM. A role só confere se os comandos existem.

---

## O Cluster Etcd

O **etcd** é o banco de dados chave-valor distribuído que armazena todo o estado do cluster Kubernetes.
* **Certificados (mTLS):** A comunicação do etcd é fortemente protegida. Foram criados certificados específicos para ele no passo de PKI (`infra-pki`), validando a identidade de cada nó e encriptando a comunicação do cluster e das respostas aos clientes (API Server).
* **Quorum:** Na configuração `completo`, 3 instâncias do etcd sobem em máquinas diferentes (os managers). O Ansible configura dinamicamente a flag `--initial-cluster` com os IPs de todos os nós para que eles se descubram e formem um quorum válido.
* **Execução (role `k8s-etcd-pod`):** O etcd é configurado como um pod estático privilegiado gerenciado pelo Kubelet, gravando os seus dados persistentes no diretório `/var/lib/etcd` montado a partir do host.
* **Ferramenta `etcdctl`:** Para evitar downloads adicionais da internet, o utilitário `etcdctl` é extraído da imagem do etcd que já está no cache OCI do host (a mesma versão do container) e instalado na máquina `kubox`, seja qual for o container runtime.

---

## O Plano de Controle (Managers)

O "cérebro" do cluster é composto por três serviços instalados nos nós Managers. Eles operam de forma interdependente e são implantados como **Static Pods** gerenciados pelo Kubelet (roles `-pod` correspondentes):

1. **kube-apiserver (role `k8s-apiserver-pod`):**
   * É o único componente que conversa diretamente com o `etcd`.
   * Recebe requisições HTTP (porta 6443), autentica e autoriza o acesso baseando-se nos certificados PKI e tokens, e expõe a API do Kubernetes.
   * Suas flags de configuração são extensas, definindo o IP no qual ele escuta as requisições (no caso, o endereço local do Manager na rede do cluster) e apontando para toda a cascata de certificados de segurança.

2. **kube-controller-manager (role `k8s-controller-manager-pod`):**
   * Roda em segundo plano avaliando o "estado atual" vs "estado desejado" dos objetos (ReplicaSets, Deployments, Nodes, etc.).
   * Ele utiliza um arquivo `kubeconfig` gerado anteriormente para se autenticar contra o `kube-apiserver`.

3. **kube-scheduler (role `k8s-scheduler-pod`):**
   * Observa os Pods que acabaram de ser criados e que não têm um nó assinalado.
   * Baseado nas restrições de recursos e labels, ele determina o melhor Worker Node para alocar o Pod.
   * Também consome seu próprio `kubeconfig` para se autenticar.
   * Na role de pod (`k8s-scheduler-pod`), a configuração foi migrada para o formato da API moderna `KubeSchedulerConfiguration` (`kubescheduler.config.k8s.io/v1`).

> 💡 Em um cenário de Alta Disponibilidade (`completo`), todos os Managers rodam esses serviços ao mesmo tempo. O `etcd` e o `kube-apiserver` operam em modo ativo-ativo (balanceados pelo HAProxy), enquanto o `controller-manager` e o `scheduler` operam em eleição de líder (ativo-passivo).

---

## Nós de Trabalho e Runtime (Workers e Managers)

Após ter o cérebro rodando, é hora de instanciar os "músculos". Embora os Managers controlem o cluster, os pods efetivamente rodam num *Runtime de Contêiner* sob o comando do `kubelet`. No *k8s-in-a-box*, por padrão, os próprios Managers também recebem a função de Workers (embora possam ser "taintados" para não rodar cargas pesadas).

1. **kubelet (role `k8s-kubelet`):**
   * O "agente" do Kubernetes. Ele lê os manifestos assinalados pelo scheduler e garante que os contêineres definidos neles estejam executando corretamente e de forma saudável.
   * **Runtime:** A variável global `container_runtime` define quem fará o peso pesado. Por padrão, o projeto instala e configura o **CRI-O**. Alternativamente, o **containerd** (com o runc) também está disponível para testes. Ambos implementam a interface CRI do Kubernetes e vêm como pacote estático, com versão fixada (`versao_crio`, `versao_containerd`, `versao_runc`); a atualização automática do SO não os atualiza.
   * **SELinux:** a role do kubelet tem o código da política customizada de SELinux (`k8s-custom-selinux`), mas ele só roda com `selinux_politica_customizada: true` (o padrão é `false`). Para detalhes, consulte a página [SELinux e Kubernetes](./selinux.md).
   * **DNS:** quando o nó usa o `systemd-resolved` (Debian), o kubelet passa aos pods o `/run/systemd/resolve/resolv.conf`, com os servidores reais. Com o `/etc/resolv.conf` do stub `127.0.0.53`, o CoreDNS encaminharia as consultas para ele mesmo.
   * O Kubelet também usa certificados para se autenticar no API Server. Na inicialização do nó, se a PKI já estiver distribuída, ele sobe; em ambientes onde os certificados não foram pré-gerados (que o k8s-in-a-box simula), ele usa uma técnica de autorização para requisitar um certificado dinamicamente (`kubelet-bootstrap`).

2. **Sem kube-proxy:**
   * O cluster não instala o `kube-proxy`. O Cilium (`kubeProxyReplacement`) faz as abstrações de **Services** funcionarem em eBPF, redirecionando o tráfego do IP do Service para os IPs reais dos Pods.

Concluída a instalação e ativação do `kubelet`, os nós informam seu status para o API Server e passam a constar no comando `kubectl get nodes` como estado `NotReady`. Eles só transitarão para `Ready` na próxima etapa: a instalação dos Addons de Rede (CNI). O Cilium é instalado a partir do bastion host `kubox`, depois que o control plane está ativo.
