# Addons e Serviços Complementares

Um cluster Kubernetes básico com apenas `etcd`, control plane e kubelets está "cego, surdo e mudo" até certo ponto: os nós rodam pods, mas eles não se comunicam entre si através dos hosts, não resolvem domínios internos e não têm armazenamento dinâmico.

O pipeline de addons e de rede do projeto foi separado em playbooks específicos. A role `addon-apps-cluster` no playbook `addons.yml` aplica a camada superior de funcionalidades de aplicação, enquanto as roles de rede e CNI (`cni-canal`, `cni-cilium`, `addon-kubevip`, `addon-traefik`, `addon-kube-proxy`) rodam no playbook `ops.yml`, transformando o esqueleto num ambiente totalmente operacional.

## Labels e Taints Iniciais

Antes de instalar aplicativos, o Ansible aplica marcações lógicas:
* **Labels** marcam os papéis (ex: `node-role.kubernetes.io/control-plane=true` nos managers e `node-role.kubernetes.io/worker=true` nos workers).
* **Taints** são aplicados aos Managers (`node-role.kubernetes.io/control-plane:NoSchedule`) caso o usuário não queira rodar pods comuns no plano de controle. No momento, o repositório permite agendamento nos managers para otimizar os recursos do cluster base.

## Plugin de Rede (CNI)

O componente mais importante de rede é o CNI (Container Network Interface). Sem ele, os nós permanecem no estado `NotReady`. Ele cuida de assinalar IPs para os Pods vindos da faixa configurada (`172.25.0.0/17`).

* **Opção 1: Canal (Padrão):**
  * Canal é a fusão de dois projetos famosos: **Calico** para Network Policies (segurança e regras de roteamento) e **Flannel** para a sobreposição da rede (VXLAN/Host-GW). É robusto, eficiente e permite cenários reais de regras de firewall internas.
* **Opção 2: Cilium (eBPF Native):**
  * Opção baseada em eBPF que atua de forma nativa e consolidada no kernel do Linux, com roteamento de alta performance e compatibilidade integrada.

O Ansible instala o CNI de acordo com a variável `plugin_cni` configurada no arquivo `inventario/group_vars/all.yml`.

## CoreDNS

Assim que a rede sobe, o **CoreDNS** é instalado (gerenciado via Helm e implantado no namespace `kube-system`).
* Ele sobe como um Pod no cluster e é responsável por ler os objetos de Serviço (`Service`) e atribuir nomes legíveis a eles.
* Permite que aplicações conversem entre si na rede do cluster usando FQDNs internos como `meu-servico.meu-namespace.svc.cluster.local`.
* **Integração com Prometheus:** Possui a exposição de métricas habilitada e um objeto `ServiceMonitor` criado com o label `release: prometheus-stack` para coleta automática de dados pelo Prometheus.

## Metrics Server

Instalado para varrer constantemente a API do kubelet em todos os nós.
* Coleciona os dados de consumo de CPU e RAM dos Pods e dos próprios Nodes.
* Sem ele, não seria possível usar o comando `kubectl top pods` ou `kubectl top nodes`, tampouco usar o Horizontal Pod Autoscaler (HPA) baseado em CPU/Memória.

## NFS Subdir External Provisioner

Conforme detalhado no arquivo [nfs.md](./nfs.md), este provisionador converte requisições de espaço em disco (PVCs) do Kubernetes em pastas criadas automaticamente no Servidor NFS exportado na rede.

## Componentes de Ingresso e Exposição

Para interagir com o mundo exterior e testar aplicações, o laboratório usa:

1. **Kube-vip & Kube-vip Cloud Provider:**
   * Kubernetes puro não sabe lidar com serviços do tipo `LoadBalancer` em infraestrutura bare-metal. O Kube-vip resolve esse problema de forma elegante.
   * Utilizando o modo L2 (Layer 2), ele responde a requisições ARP no lugar dos roteadores e propaga os IPs virtuais (VIPs) diretamente nos nós do cluster.
   * O `kube-vip-cloud-provider` atua como um controlador IPAM local, distribuindo automaticamente IPs do pool configurado (`kubevip_ips_loadbalacing`) ou atribuindo IPs fixos (`kubevip_ips_manuais`) especificados nas anotações dos serviços.
   * **Egress Gateway:** Permite que o tráfego originado em pods específicos saia do cluster utilizando um IP estático dedicado (para acessar serviços externos). Para utilizá-lo, basta criar um serviço do tipo `LoadBalancer` configurando a anotação `kube-vip.io/egress: "true"` (com o IP em `kube-vip.io/loadbalancerIPs`) e a especificação `externalTrafficPolicy: Local`.
     > 💡 **Nota de CNI**: O projeto configura automaticamente o Calico com `chainInsertMode: Append` para evitar que as regras de NAT do Kube-vip conflitem com o tráfego interno do cluster.

2. **Traefik Gateway API:**
   * A evolução moderna do antigo conceito de Ingress Controllers. O Gateway API lida com roteamento HTTP avançado e o Traefik atua como essa "porta de entrada inteligente", escutando portas 80/443 do mundo exterior e direcionando o fluxo aos pods do cluster.

## Headlamp Dashboard

Uma interface visual elegante, robusta e leve, instalada no cluster como forma fácil de visualizar todos os recursos (pods, logs, métricas, roles).
O painel é acessado através do serviço Traefik criado por padrão e protegido com um ServiceAccount token (exemplo contido no `README.md` da raiz).

## Vertical Pod Autoscaler (VPA)

O **Vertical Pod Autoscaler (VPA)** é um addon essencial para otimização de recursos do cluster. Enquanto o HPA (Horizontal Pod Autoscaler) redimensiona a quantidade de réplicas de uma aplicação de acordo com a carga, o VPA atua ajustando os recursos (solicitações e limites de CPU e memória) solicitados pelos contêineres dos Pods de forma vertical.

* **Namespace de Instalação:** `vpa`
* **Chart Helm:** `autoscalers/vertical-pod-autoscaler` (repositório `https://kubernetes.github.io/autoscaler`)
* **Modos de Funcionamento (`updateMode`):**
  * **`Off`:** O VPA apenas gera recomendações estáticas sobre os recursos que o Pod deveria estar consumindo (visualizáveis via `kubectl describe vpa`). É o modo ideal e obrigatório quando se deseja utilizar o VPA em conjunto com o HPA (para evitar conflitos em que ambos tentam escalar as réplicas/recursos concorrentemente).
  * **`Initial`:** O VPA atribui recursos recomendados no momento da criação do Pod, mas não altera um Pod que já esteja em execução. Muito útil para CronJobs ou tarefas que rodam periodicamente.
  * **`Auto` / `Recreate`:** O VPA despeja (evict) os pods ativos para recriá-los com as novas configurações de CPU/memória ideais (não recomendado em cenários com HPA).

## Stack de Observabilidade (Prometheus Stack + Grafana)

Para monitoramento completo de infraestrutura e aplicações, o projeto instala a stack de observabilidade nativa baseada no Prometheus Operator.

* **Namespace de Instalação:** `monitoring`
* **Chart Helm:** `prometheus-community/kube-prometheus-stack`
* **Componentes Principais:**
  * **Prometheus:** Servidor de monitoramento principal com limite de retenção configurado para 3 dias (`retention: 3d`). Configurado com solicitações de recursos de `100m` CPU e `400Mi` RAM (limites de `500m` CPU e `1Gi` RAM).
  * **Grafana:** Painel de visualização rico. Exposto via `LoadBalancer` Kube-vip com o IP fixo configurado `172.24.0.103`.
  * **Alertmanager:** Desabilitado por padrão (`alertmanager.enabled: false`) para economia de recursos no ambiente local.
* **Dashboards Pré-carregados:**
  O Grafana vem integrado de fábrica com dashboards da comunidade (`dotdc/grafana-dashboards-kubernetes`):
  * `k8s-views-global` (dashboard padrão inicial / home)
  * `k8s-system-api-server`
  * `k8s-system-coredns`
  * `k8s-views-namespaces`
  * `k8s-views-nodes`
  * `k8s-views-pods`
* **Monitoramento do Control Plane (Static Pods):**
  Ao contrário de clusters gerenciados tradicionais, monitoramos os componentes nativos que rodam como Static Pods nos nós Managers. A stack está configurada para mapear endpoints estáticos dos managers e raspar métricas diretamente deles:
  * `kubeControllerManager` e `kubeScheduler` usam `insecureSkipVerify: true`.
  * `kubeEtcd` usa esquema `http`.
* **Monitoramento do kube-proxy:**
  As métricas do `kube-proxy` são raspadas via porta `10249`, configurada para responder na interface `0.0.0.0`.
* **Como obter a senha de administrador do Grafana:**
  O usuário padrão é `admin`. A senha gerada aleatoriamente durante a instalação pode ser obtida executando o seguinte comando no terminal do cluster:
  ```bash
  kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
  ```
