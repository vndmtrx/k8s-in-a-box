# Addons e Serviços Complementares

Um cluster Kubernetes básico com apenas `etcd`, control plane e kubelets está "cego, surdo e mudo" até certo ponto: os nós rodam pods, mas eles não se comunicam entre si através dos hosts, não resolvem domínios internos e não têm armazenamento dinâmico.

A role `13-addons-cluster` no projeto aplica a camada superior de funcionalidades, transformando o esqueleto num ambiente totalmente operacional.

## Labels e Taints Iniciais

Antes de instalar aplicativos, o Ansible aplica marcações lógicas:
* **Labels** marcam os papéis (ex: `node-role.kubernetes.io/control-plane=true` nos managers e `node-role.kubernetes.io/worker=true` nos workers).
* **Taints** são aplicados aos Managers (`node-role.kubernetes.io/control-plane:NoSchedule`) caso o usuário não queira rodar pods comuns no plano de controle. No momento, o repositório permite agendamento nos managers para otimizar os recursos do cluster base.

## Plugin de Rede (CNI)

O componente mais importante de addon é o CNI (Container Network Interface). Sem ele, os nós permanecem no estado `NotReady`. Ele cuida de assinalar IPs para os Pods vindos da faixa configurada (`172.25.0.0/17`).

* **Opção 1: Canal (Padrão):**
  * Canal é a fusão de dois projetos famosos: **Calico** para Network Policies (segurança e regras de roteamento) e **Flannel** para a sobreposição da rede (VXLAN/Host-GW). É robusto, eficiente e permite cenários reais de regras de firewall internas.
* **Opção 2: Flannel Simples:**
  * Opção leve focada inteiramente em criar o túnel de comunicação entre os nós, ideal para ambientes onde memória é estritamente limitante (como a configuração `nano`).

O Ansible baixa os manifestos YAML de acordo com a variável `plugin_cni` e injeta a faixa CIDR de pods definida na variável `rede_cidr_pods` (dentro de `inventario/group_vars/all.yml`).

## CoreDNS

Assim que a rede sobe, o **CoreDNS** é instalado (frequentemente com a ajuda do Helm, gerenciado localmente pelo bastion host ou scripts diretos).
* Ele sobe como um Pod no cluster e é responsável por ler os objetos de Serviço (`Service`) e atribuir nomes legíveis a eles.
* Permite que aplicações conversem entre si na rede do cluster usando FQDNs internos como `meu-servico.meu-namespace.svc.cluster.local`.

## Metrics Server

Instalado para varrer constantemente a API do kubelet em todos os nós.
* Coleciona os dados de consumo de CPU e RAM dos Pods e dos próprios Nodes.
* Sem ele, não seria possível usar o comando `kubectl top pods` ou `kubectl top nodes`, tampouco usar o Horizontal Pod Autoscaler (HPA) baseado em CPU/Memória.

## NFS Subdir External Provisioner

Conforme detalhado no arquivo [nfs.md](./nfs.md), este provisionador converte requisições de espaço em disco (PVCs) do Kubernetes em pastas criadas automaticamente no Servidor NFS exportado na rede.

## Componentes de Ingresso e Exposição

Para interagir com o mundo exterior e testar aplicações, o laboratório usa:

1. **MetalLB:**
   * Kubernetes puro não sabe lidar com serviços do tipo `LoadBalancer` em infraestrutura bare-metal. O MetalLB preenche essa lacuna.
   * Utilizando o modo L2 (Layer 2), ele assume pools de IPs previamente declarados no Ansible (como `172.24.0.101-172.24.0.150`), respondendo a requisições ARP no lugar dos roteadores e repassando para os nós corretos.
2. **Traefik Gateway API:**
   * A evolução moderna do antigo conceito de Ingress Controllers. O Gateway API lida com roteamento HTTP avançado e o Traefik atua como essa "porta de entrada inteligente", escutando portas 80/443 do mundo exterior e direcionando o fluxo aos pods do cluster.

## Headlamp Dashboard

Uma interface visual elegante, robusta e leve, instalada no cluster como forma fácil de visualizar todos os recursos (pods, logs, métricas, roles).
O painel é acessado através do serviço Traefik criado por padrão e protegido com um ServiceAccount token (exemplo contido no `README.md` da raiz).
