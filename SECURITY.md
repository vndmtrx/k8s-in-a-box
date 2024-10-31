# Política de Segurança

## Visão Geral
Este documento descreve as diretrizes de segurança implementadas neste projeto educacional de instalação do Kubernetes, inspirado no guia "[Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)". O projeto demonstra uma instalação completa, desde a infraestrutura básica até implantações funcionais, utilizando o Ansible para automação.

## Objetivo Educacional
Este projeto serve como:
- Ambiente de aprendizagem para instalação manual do Kubernetes
- Demonstração de boas práticas de segurança
- Guia prático para compreensão da infraestrutura de chaves públicas (PKI)
- Exemplo de automatização com Ansible
- Laboratório para testes de recursos do Kubernetes

## Infraestrutura

### Certificados e PKI
- Implementação de PKI própria utilizando:
  - Curva Ed25519 (mais moderna que RSA)
  - Função de hash SHA-512 para maior segurança
  - Autoridades Certificadoras (CAs) distintas para etcd e Kubernetes
- Prazos de validade configuráveis via variáveis do Ansible:
  - CAs: 10 anos (`pki_validade_ca: 3650`)
  - Certificados: 1 ano (`pki_validade_cert: 365`)

### Ambiente de Laboratório
- Virtualização via Vagrant com LibVirt
- Rede isolada (172.24.0.0/24)
- Arquitetura em camadas:
  - Balanceador de carga frontal (HAProxy)
  - Plano de Controle com 3 nós
  - Nós de trabalho para execução de cargas
  - MetalLB para serviços de balanceamento de carga

### Controle de Acesso
- Demonstração de boas práticas:
  - Chaves Ed25519 para acesso SSH
  - Usuário sem privilégios de root (vagrant)
  - Elevação de privilégios configurada via Ansible
- Observação: configurações simplificadas para ambiente de estudos

## Componentes do Cluster

### Balanceamento de Carga
- HAProxy:
  - Terminação TLS
  - Distribuição de carga do Plano de Controle
  - Monitoramento de integridade dos pontos de acesso
- MetalLB:
  - Modo camada 2 para ambiente local
  - Integração com serviços Kubernetes
  - Faixa de endereços IP configurável

### Rede
- Flannel CNI:
  - Rede sobreposta VXLAN
  - Isolamento de contêineres
  - Políticas básicas de rede
- Malha de Serviços (planejado):
  - Exemplo de implementação
  - Monitoramento de tráfego
  - Políticas granulares de acesso

### etcd
Demonstração de segurança do etcd:
- TLS mútuo em todas as comunicações
- Certificados específicos por função
- Separação clara de responsabilidades:
  - Certificados para servidores
  - Certificados para comunicação entre pares
  - Certificados para clientes (HAProxy/API Server)

### Núcleo do Kubernetes
Implementação didática dos componentes principais:
- Servidor de API com TLS
- Kubelet com autenticação por certificado
- Arquivo de configuração (kubeconfig) gerado automaticamente
- Controle de acesso básico demonstrativo (RBAC)

## Exemplos Práticos

### Implantações Demonstrativas
O projeto inclui exemplos de:
- Aplicações sem estado
- Aplicações com estado
- Configurações de entrada (Ingress)
- Gerenciamento de segredos
- Mapas de configuração
- Volumes persistentes

### Políticas de Rede
Exemplos de controle de tráfego:
- Isolamento de espaços de nome
- Regras de entrada e saída
- Políticas baseadas em rótulos
- Segmentação de rede refinada

### Exposição de Serviços
Demonstrações de:
- IP interno do cluster (ClusterIP)
- Porta do nó (NodePort)
- Balanceador de carga via MetalLB
- Entrada com TLS

## Guia de Contribuição
Este é um projeto educacional aberto a contribuições. Para contribuir:
1. Faça uma cópia do repositório
2. Crie um ramo para sua funcionalidade
3. Mantenha o foco educacional
4. Documente alterações de segurança
5. Envie um pedido de incorporação

## Avisos Importantes

### Ambiente de Produção
Este projeto NÃO deve ser usado em produção sem modificações significativas:
- Políticas mais rigorosas são necessárias
- Rotação de certificados deve ser implementada
- Sistema de monitoramento precisa ser adicionado
- Fortalecimento adicional de segurança é necessário
- Políticas de rede mais restritivas
- Configuração real de alta disponibilidade

### Finalidade Educacional
- Projeto focado em aprendizagem
- Algumas configurações são simplificadas
- Use como material de estudo
- Implemente controles adicionais para produção

## Comunicação de Problemas

### Questões de Segurança
Para reportar problemas de segurança:
1. Abra uma ocorrência detalhada
2. Utilize a etiqueta "segurança"
3. Explique o impacto educacional
4. Sugira melhorias didáticas

## Referências
- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Documentação de Segurança do Kubernetes](https://kubernetes.io/docs/concepts/security/)
- [Modelo de Segurança do etcd](https://etcd.io/docs/latest/op-guide/security/)
- [Boas Práticas de PKI](https://kubernetes.io/docs/setup/best-practices/certificates/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [MetalLB](https://metallb.universe.tf/)
- [Boas Práticas do HAProxy](https://www.haproxy.com/blog/the-four-essential-sections-of-an-haproxy-configuration/)

## Licença
Este projeto é distribuído sob a licença MIT, permitindo uso educacional e derivações, desde que mantidos os créditos originais.
