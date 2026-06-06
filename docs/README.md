# Documentação do k8s-in-a-box

Bem-vindo à documentação do projeto **k8s‑in‑a-box**. Nesta seção são reunidos materiais que descrevem a arquitetura do cluster, os componentes instalados e as operações necessárias para provisionar e gerenciar um cluster Kubernetes utilizando **Ansible** e **Vagrant**.

## Índice

1. **[Visão geral da estrutura do cluster](./estrutura.md)**: descreve a topologia do cluster, funções de cada componente (balanceadores, servidor NFS, managers, workers e kubox) e os addons instalados.
1. **[Configurações de Cluster](./configuracoes.md)**: explica as três configurações pré-definidas (nano, mini, completo) e como gerenciá-las usando o sistema de symlinks do Makefile.
1. **[Estrutura de Chaves PKI](./estrutura-pki.md)**: descreve o processo de organização da geração dos CAs e dos Certificados usados nos diferentes componentes do cluster.
1. **[Balanceadores de carga](./balanceadores.md)**: detalhes sobre a configuração do HAProxy e do Keepalived, incluindo VIPs e distribuição de requisições.
1. **[Servidor NFS e armazenamento](./nfs.md)**: explica o setup do servidor NFS e o provisionamento de volumes dinâmicos.
1. **[Plano de controle e nós de trabalho](./nodes.md)**: aborda a instalação do `etcd`, API Server, Controller Manager, Scheduler, `kubelet`, `containerd` e `kube‑proxy`.
1. **[SELinux e Kubernetes](./selinux.md)**: documenta a política customizada de SELinux, as decisões de hardening e a integração com o kubelet, os containers e os pods do cluster.
1. **[Addons e serviços complementares](./addons.md)**: plugins de rede (CNI), CoreDNS, Metrics Server, NFS Subdir Provisioner, Kube-vip, Gateway API (Traefik), Headlamp Dashboard, VPA e stack de observabilidade (kube-prometheus-stack + Grafana).
1. **[Vagrant, Makefile e redes](./provisionamento.md)**: descreve a criação das VMs via Vagrant, as opções do Makefile e a configuração de rede tanto no `Vagrantfile` quanto no cluster.
1. **[Aplicações de Exemplo e Segurança](./exemplos.md)**: detalha os deploys de demonstração (`hello-app` e `contador`), a arquitetura para execução não-root (rootless) e a validação de 100% de conformidade no Popeye.

## Sobre

O conteúdo aqui disponibilizado tenta seguir à risca os padrões de melhores práticas em **Ansible** e **Vagrant**, com variáveis e exemplos em português sempre que possível. Quando existem métodos alternativos para realizar uma mesma atividade, eles são apresentados para que o leitor possa escolher a abordagem mais apropriada. Para detalhes de implementação, consulte os arquivos e seções correspondentes indicadas no índice.
