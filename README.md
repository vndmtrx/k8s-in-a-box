# 🧩 k8s-in-a-jar

Kubernetes in a Jar - Uma instalação de Kubernetes focada em instalação sem helpers e usando Ansible como provisionador.

Uma implementação inspirada no conceito "Kubernetes The Hard Way", utilizando Ansible como ferramenta de automação. Este projeto visa proporcionar uma compreensão maior do funcionamento interno do Kubernetes através da instalação e configuração manual de cada componente, sem depender de ferramentas de conveniência como `kubeadm` ou `k3s`.

A abordagem manual de instalação deste projeto permite explorar a arquitetura e os fundamentos do Kubernetes, sendo particularmente relevante para profissionais interessados em entender os mecanismos internos de um cluster Kubernetes.

## 🚀 Estado Atual do Projeto

Este projeto está em desenvolvimento ativo, seguindo uma abordagem progressiva de construção do cluster Kubernetes. A implementação segue uma sequência lógica que respeita as dependências entre os componentes.

### 🟢 Componentes Concluídos
- Infraestrutura com Vagrant/LibVirt
- Framework de Automação Ansible
- Sistema Base das VMs (Debian Bookworm)
- PKI (Certificados para todos componentes)

### 🟡 Em Desenvolvimento
1. **Load Balancer (HAProxy)**
   - Balanceamento do API Server
   - Balanceamento do etcd
   - Configuração de Health Checks

2. **Cluster etcd**
   - Implementação do cluster distribuído
   - Configuração de alta disponibilidade
   - Integração com HAProxy

3. **Kubernetes API Server**
   - Integração com etcd
   - Configuração de alta disponibilidade
   - Balanceamento via HAProxy

### ⚪ Etapas Futuras
- Demais Componentes do Control Plane
- Workers, Kubelet e Container Runtime
- Rede do Cluster
- MetalLB
- Sistema de Monitoramento
- Componentes Adicionais
- Exemplos e demonstrações de uso do cluster

> 📖 Para um acompanhamento detalhado do desenvolvimento, incluindo todos os componentes e suas dependências, consulte o [Mapa de Progresso](docs/PROGRESS.md).

📑 [Ver progresso detalhado](docs/PROGRESSO.md)

## Arquitetura

O cluster é composto por:
- 1 Load Balancer
- 3 Managers (Control Plane)
- 2 Workers

## Pré-requisitos

- Vagrant com provider LibVirt
- Ansible 2.9+
- Debian Bookworm 64-bit (base para as VMs)
- 9.5 GB RAM disponível
- 9 vCPUs disponíveis

## Início Rápido

1. Clone o repositório:
```bash
git clone https://github.com/vndmtrx/k8s-in-a-jar.git
cd k8s-in-a-jar
```

2. Inicie as VMs:
```bash
vagrant up
```

3. Execute o provisionamento:
```bash
./provisionamento.sh
```

## Acessando as VMs

Use o comando SSH com o arquivo de configuração fornecido neste repositório:
```bash
ssh -F ssh_config 172.24.0.11  # Load Balancer
ssh -F ssh_config 172.24.0.21  # Manager 1
ssh -F ssh_config 172.24.0.22  # Manager 2
ssh -F ssh_config 172.24.0.23  # Manager 3
ssh -F ssh_config 172.24.0.31  # Worker 1
ssh -F ssh_config 172.24.0.32  # Worker 2
```

## Rede

Todas as máquinas estão em uma rede privada:
- Load Balancer: 172.24.0.11
- Manager 1: 172.24.0.21
- Manager 2: 172.24.0.22
- Manager 3: 172.24.0.23
- Worker 1: 172.24.0.31
- Worker 2: 172.24.0.32

## Notas Importantes

- A chave SSH gerada por esse Vagrant (`id_ed25519.pub`) é apenas para exemplo/desenvolvimento
- **NÃO USE** esta chave em ambiente de produção
- Para produção, sempre gere e use suas próprias chaves SSH
- O script `provisionamento.sh` utiliza uma configuração específica do Ansible localizada em `./ansible/.ansible.cfg`

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE) - veja o arquivo LICENSE para detalhes.

## Nota Pessoal

Este repositório representa meu aprendizado sobre Kubernetes. Este projeto não é apenas uma implementação, mas um caminho de estudo estruturado para compreender cada aspecto do funcionamento do Kubernetes.

---

⚠️ **Projeto em desenvolvimento**