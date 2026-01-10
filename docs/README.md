# Documentação do k8s-in-a-box

Bem-vindo à documentação do projeto **k8s‑in‑a-box**. Nesta seção são reunidos materiais que descrevem a arquitetura do cluster, os componentes instalados e as operações necessárias para provisionar e gerenciar um cluster Kubernetes utilizando **Ansible** e **Vagrant**.

## Índice

1. **[Visão geral da estrutura do cluster](./estrutura.md)** – Descreve a topologia do cluster, funções de cada componente (balanceadores, servidor NFS, managers, workers e kubox) e os addons instalados.
1. **[Configurações de Cluster](./configuracoes.md)** – Explica as três configurações pré-definidas (nano, mini, completo) e como gerenciá-las usando o sistema de symlinks do Makefile.
1. **[Estrutura de Chaves PKI](./estrutura-pki.md)** - Descreve o processo de organização da geração dos CAs e dos Certificados usados nos diferentes componentes do cluster.
1. **[Balanceadores de carga](./balanceadores.md)** – Detalhes sobre a configuração do HAProxy e do Keepalived, incluindo VIPs e distribuição de requisições.
1. **[Servidor NFS e armazenamento](./nfs.md)** – Explica o setup do servidor NFS e o provisionamento de volumes dinâmicos.
1. **[Plano de controle e nós de trabalho](./nodos.md)** – Aborda a instalação do `etcd`, API Server, Controller Manager, Scheduler, `kubelet`, `containerd` e `kube‑proxy`.
1. **[Addons e serviços complementares](./addons.md)** – Introdução aos plugins de rede, CoreDNS, Metrics Server, Ingress Controller, NFS Subdir Provisioner, MetalLB e Kubernetes Dashboard.
1. **[Vagrant, Makefile e redes](./provisionamento.md)** – Descreve a criação das VMs via Vagrant, as opções do Makefile e a configuração de rede tanto no `Vagrantfile` quanto no cluster

## Sobre

O conteúdo aqui disponibilizado tenta seguir à risca os padrões de melhores práticas em **Ansible** e **Vagrant**, com variáveis e exemplos em português sempre que possível. Quando existem métodos alternativos para realizar uma mesma atividade, eles são apresentados para que o leitor possa escolher a abordagem mais apropriada. Para detalhes de implementação, consulte os arquivos e seções correspondentes indicadas no índice.
