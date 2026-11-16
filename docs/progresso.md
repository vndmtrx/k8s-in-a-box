# 📋 Acompanhamento Detalhado do Projeto

> ⚠️ Este documento é atualizado frequentemente para refletir o estado atual do projeto.

## 📋 Progresso do Projeto

### Infraestrutura Base
- [x] Criação das VMs no libvirt pelo Ansible (o Vagrant saiu em 2026-11)
- [x] Configuração do Ansible
- [x] Configuração da Rede
- [x] Preparação do Sistema Base (cloud-init)
- [x] Duas distribuições: Debian 13 (padrão) e AlmaLinux 10

### 🔐 PKI (Public Key Infrastructure)
- [x] Root CA do projeto
- [x] CA do etcd
- [x] CA do Kubernetes
- [x] Certificados do etcd (servidor/cliente/peer)
- [x] Certificados do kube-apiserver
- [x] Certificados dos kubelets
- [x] Certificados dos componentes do control plane
- [x] Certificados de administração

### 🔄 Load Balancer
- [x] Instalação do HAProxy
- [x] Configuração do balanceamento do kube-apiserver
- [x] Configuração do balanceamento do etcd
- [x] Configuração do monitoramento de saúde (health checks)
- [x] Interface de estatísticas do HAProxy

### 📦 Cluster etcd
- [x] Instalação do etcd
- [x] Configuração do cluster etcd

### 🎮 Control Plane
- [x] Configuração do etcd como backend (Static Pod) via role `k8s-etcd-pod`
- [x] Instalação do kube-apiserver (Static Pod) via role `k8s-apiserver-pod`
- [x] Configuração do kube-controller-manager (Static Pod) via role `k8s-controller-manager-pod`
- [x] Configuração do kube-scheduler (Static Pod) via role `k8s-scheduler-pod`
- [x] Geração dos arquivos kubeconfig
  - [x] kubeconfig do admin
  - [x] kubeconfig do controller-manager
  - [x] kubeconfig do scheduler
  - [x] kubeconfig do kubelet (para cada nó)
  - [x] ~kubeconfig do kube-proxy~ (Substituído por ServiceAccount nativo do Pod)

### 👷 Workers
- [x] Configuração do Container Runtime
  - [x] Escolha do runtime (containerd/CRI-O)
  - [x] Instalação e configuração
- [x] Instalação do kubelet
- [x] Política customizada de SELinux (Type Enforcement), hoje desligada por flag
- [x] ~Configuração do kube-proxy~ (o Cilium substitui o kube-proxy)

### 🌐 Rede do Cluster
- [x] Escolha do CNI Plugin
  - [x] Instalação do plugin escolhido
  - [x] Configuração da rede dos pods
  - [x] Configuração da rede dos serviços
- [x] Instalação do CoreDNS
- [x] ~Configuração do Kube-vip~ (os IPs de LoadBalancer vêm do LB IPAM do Cilium)
- [x] Configuração do Gateway API
- [x] Validação da rede

### 📊 Addons e Observabilidade
- [x] Vertical Pod Autoscaler (VPA)
- [x] Stack de Observabilidade (kube-prometheus-stack + Grafana)
- [x] ServiceMonitor do CoreDNS integrado ao Prometheus
- [x] ~Métricas do kube-proxy expostas para o Prometheus~ (sem kube-proxy)

### ✅ Validação
- [x] Testes de conformidade com o Sonobuoy (469 testes, 0 falhas, nas duas distros)

### 📚 Documentação
- [x] README do Projeto
- [ ] Guia de Instalação
- [ ] Guia de Operação
- [ ] Guia de Troubleshooting
- [ ] Guia de Backup e Recuperação
- [ ] Guia de Atualização

---

📝 **Notas:**
- Cada etapa inclui testes e validação
- A documentação é atualizada a cada etapa
- Checkpoints de segurança são realizados em cada fase
