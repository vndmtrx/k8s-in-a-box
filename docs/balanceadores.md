# Balanceadores de Carga

No projeto **k8s-in-a-box**, a alta disponibilidade do plano de controle é garantida pela atuação conjunta do **HAProxy** e do **Keepalived**. Estes componentes residem em nós dedicados (como `loadbalancer1` e `loadbalancer2`), funcionando como ponto de entrada único e resiliente para o cluster.

A automação desses nós é conduzida pela role Ansible `03-balanceador`.

## HAProxy

O **HAProxy** atua como um proxy reverso TCP e HTTP rápido e confiável, realizando o balanceamento de carga para os componentes críticos do control plane.

### Como funciona

O HAProxy é configurado para escutar portas específicas e distribuir o tráfego de maneira eficiente entre os Managers disponíveis. As configurações principais aplicadas incluem:

* **API Server (Porta 6443):**
  * O frontend recebe requisições destinadas à API do Kubernetes na porta padrão 6443.
  * O backend distribui essas requisições entre os nós do tipo Manager (ex: `172.24.0.31`, `172.24.0.32`, etc.).
  * O modo de balanceamento utilizado garante que, se um manager cair, o tráfego é redirecionado instantaneamente para os saudáveis.
* **Etcd (Porta 2379):**
  * O tráfego de comunicação de clientes com o banco distribuído `etcd` também passa pelo HAProxy para otimização de rotas e failover, enviando tráfego aos membros vivos do cluster etcd.
* **Página de Status:**
  * O HAProxy expõe uma interface web para monitoramento na porta `9000`.
  * Pode ser acessada em `http://<IP-DO-LOADBALANCER>:9000/stats`.
  * As credenciais padrão estão definidas nas variáveis em `inventario/group_vars/all.yml` (geralmente usuário `admin`).

A configuração do HAProxy é gerada a partir de templates (`haproxy.cfg.j2`) que mapeiam dinamicamente o grupo de `managers` do Ansible. Antes de reiniciar o serviço após alguma alteração, o Ansible realiza um check de sintaxe na configuração.

## Keepalived

Enquanto o HAProxy balanceia o tráfego que chega até ele, o **Keepalived** garante que o próprio HAProxy seja altamente disponível (na configuração `completo`, onde existem múltiplos balanceadores).

### Virtual IP (VIP) e Failover

O Keepalived implementa o protocolo VRRP (Virtual Router Redundancy Protocol). Seu objetivo é gerenciar um **Endereço IP Virtual (VIP)** compartilhado entre os nós balanceadores.

* **O VIP:**
  * No `k8s-in-a-box`, o VIP configurado para o plano de controle é `172.24.0.10` (controlado pela variável `keepalived_vip_ip`).
  * Esse é o endereço que os componentes (como o `kubelet` nos workers ou o `kubectl` no kubox) utilizam para conversar com o cluster.
* **Ativo-Passivo:**
  * Apenas um nó balanceador possui o VIP por vez (estado MASTER). Os outros monitoram (estado BACKUP).
  * Se o nó MASTER cair, o Keepalived move rapidamente o VIP (`172.24.0.10`) para um dos nós BACKUP.
* **Health Checks:**
  * O Keepalived monitora constantemente a saúde do processo do HAProxy (via script de check na porta tcp do proxy). Se o HAProxy de uma máquina MASTER falhar, o Keepalived cede o VIP para outra máquina, mitigando pontos únicos de falha.

> 💡 **Nota Prática:** Mesmo em configurações como a `nano` ou `mini` (onde existe apenas 1 nó load balancer), o Keepalived é instalado. Isso garante que o cluster sempre dependa de um IP lógico (`172.24.0.10`), mantendo a arquitetura uniforme para quando houver transição para a topologia `completa`.

## Resumo do Fluxo

1. O `kubectl` (ou `kubelet`) dispara uma chamada para `https://172.24.0.10:6443`.
2. Essa chamada atinge a interface de rede do nó Load Balancer MASTER que está atualmente detendo o VIP gerenciado pelo **Keepalived**.
3. O **HAProxy** nesse nó intercepta a requisição na porta 6443.
4. O HAProxy consulta seus backends disponíveis e repassa a requisição para um Manager funcional (ex: `https://172.24.0.31:6443`).
5. O Manager processa e responde.

Essa abstração garante que serviços possam ser adicionados, removidos ou reiniciados no backend sem interromper a disponibilidade do cluster Kubernetes.
