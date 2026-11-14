# Addons e Serviços Complementares

Um cluster Kubernetes básico com apenas `etcd`, control plane e kubelets está "cego, surdo e mudo" até certo ponto: os nós rodam pods, mas eles não se comunicam entre si através dos hosts, não resolvem domínios internos e não têm armazenamento dinâmico.

O pipeline de addons e de rede do projeto foi separado em playbooks específicos. A role `addon-apps-cluster` no playbook `addons.yml` aplica a camada superior de funcionalidades de aplicação, enquanto a role de rede `cni-cilium` roda no playbook `ops.yml`, transformando o esqueleto num ambiente totalmente operacional.

## Labels e Taints Iniciais

Antes de instalar aplicativos, o Ansible aplica marcações lógicas:
* **Labels** marcam os papéis (ex: `node-role.kubernetes.io/control-plane=true` nos managers e `node-role.kubernetes.io/worker=true` nos workers).
* **Taints** são aplicados aos Managers (`node-role.kubernetes.io/control-plane:NoSchedule`) caso o usuário não queira rodar pods comuns no plano de controle. No momento, o repositório permite agendamento nos managers para otimizar os recursos do cluster base.

## Plugin de Rede (CNI)

O componente mais importante de rede é o CNI (Container Network Interface). Sem ele, os nós permanecem no estado `NotReady`. Ele cuida de assinalar IPs para os Pods vindos da faixa configurada (`172.25.0.0/17`).

O projeto usa o **Cilium**:
  * O Cilium é um plugin de rede baseado em **eBPF** (Extended Berkeley Packet Filter) que roda de forma nativa e consolidada diretamente no kernel do Linux. Ele substitui regras complexas do iptables por programas eBPF rápidos, oferecendo roteamento de altíssima performance, balanceamento de serviços e políticas de segurança robustas.
  * **Hubble UI:** Habilita um console visual de observabilidade que exibe em tempo real o fluxo de rede, requisições HTTP e possíveis quedas ou bloqueios de tráfego entre pods.
  * **IPAM & L2:** Possui mecanismos nativos de IPAM (gerenciamento de blocos de IPs) e anúncio L2 (ARP), sem componentes auxiliares de LoadBalancer em redes bare-metal.
  * **Sem kube-proxy:** o `kubeProxyReplacement` faz o balanceamento dos serviços em eBPF, então o cluster não instala o `kube-proxy`.
  * **Gateway API Nativamente:** O Cilium atua diretamente como controller da especificação Gateway API, utilizando um Envoy integrado para processar e rotear o tráfego externo sem um Ingress/Gateway Controller separado.

> O Canal (Calico + Flannel), que vinha acompanhado de kube-proxy, Kube-vip e Traefik, saiu do projeto em 2026-11. Manter dois caminhos de rede dobrava a matriz de testes, e o caminho alternativo quebrava sem ninguém notar.

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

O roteamento externo e a alocação de IPs de LoadBalancer ficam com o Cilium:
* **LoadBalancer IPAM & L2 Announcement:** O próprio Cilium gerencia os pools de IPs do LoadBalancer (`lb_ips_fixos` e `lb_ips_dinamicos`) e anuncia os IPs via ARP de forma nativa para a rede.
* **Cilium Gateway (Envoy):** O Cilium atua como o controller oficial do Gateway API, processando diretamente recursos do tipo `Gateway` e `HTTPRoute` através do Envoy.
* **Hubble UI Dashboard:** O painel do Hubble UI é provisionado no IP de LoadBalancer `172.24.0.104`.
* **Headlamp Dashboard:** O dashboard administrativo é exposto através do Gateway e Envoy do Cilium no IP de LoadBalancer `172.24.0.101`.

---

## Headlamp Dashboard

Uma interface visual elegante, robusta e leve, instalada no cluster como forma fácil de visualizar todos os recursos (pods, logs, métricas, roles).
O painel é acessado através do IP de LoadBalancer `172.24.0.101` (exposto pelo Cilium) e protegido com um token de ServiceAccount (veja instruções no `README.md` da raiz).

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

* **Namespace de Instalação:** `monitoramento`
* **Chart Helm:** `prometheus-community/kube-prometheus-stack`
* **Componentes Principais:**
  * **Prometheus:** Servidor de monitoramento principal com limite de retenção configurado para 3 dias (`retention: 3d`). Configurado com solicitações de recursos de `100m` CPU e `400Mi` RAM (limites de `500m` CPU e `1Gi` RAM).
  * **Grafana:** Painel de visualização rico. Exposto via serviço do tipo `LoadBalancer` com o IP fixo `172.24.0.103` (entregue e anunciado pelo Cilium).
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
* **Como obter a senha de administrador do Grafana:**
  O usuário padrão é `admin`. A senha gerada aleatoriamente durante a instalação pode ser obtida executando o seguinte comando no terminal do cluster:
  ```bash
  kubectl get secret -n monitoramento prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
  ```
