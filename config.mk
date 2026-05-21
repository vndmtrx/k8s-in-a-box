# ==============================================================================
# K8s in a Box - Configurações Locais
# ==============================================================================
# Este arquivo define o tipo de cluster e o método de instalação.
# Após alterar os valores abaixo, execute `make init` para aplicar a configuração.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CLUSTER: Define a topologia do cluster e os recursos alocados
# ------------------------------------------------------------------------------
# Opções disponíveis:
#   - nano     : 1 Control Plane, 1 Worker, 1 NFS, 1 Load Balancer, 1 Bastion
#                (Ideal para testes rápidos. Mínimo de ~6GB RAM / 6 vCPUs)
#
#   - mini     : 1 Control Plane, 2 Workers, 1 NFS, 1 Load Balancer, 1 Bastion
#                (Configuração padrão do projeto. Recomendado ~10GB RAM / 9 vCPUs)
#
#   - completo : 3 Control Planes (HA quorum), 2 Workers, 1 NFS, 2 Load Balancers
#                (HA com Keepalived), 1 Bastion. (Ideal para simular produção/HA.
#                Recomendado ~19GB RAM / 18 vCPUs)
#
CLUSTER = mini

# ------------------------------------------------------------------------------
# 2. INSTALACAO: Define o método de provisionamento do Control Plane
# ------------------------------------------------------------------------------
# Opções disponíveis:
#   - bin : Instala e gerencia os componentes do Control Plane (API server,
#           controller-manager, scheduler, etcd) diretamente como binários rodando
#           via systemd (modo tradicional).
#
#   - pod : Executa os componentes do Control Plane como Static Pods dentro do
#           Kubernetes (gerenciados pelo Kubelet).
#
INSTALACAO = bin
