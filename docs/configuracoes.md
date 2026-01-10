# Configurações de Cluster

O **k8s-in-a-box** oferece um sistema de configurações que permite alternar entre diferentes topologias de cluster, cada uma otimizada para cenários específicos de uso e recursos disponíveis.

## Visão Geral

O projeto utiliza um sistema baseado em **symlinks** para gerenciar configurações de cluster. Em vez de manter um único arquivo `inventario/hosts.yml` fixo, o Makefile cria um link simbólico que aponta para uma das configurações pré-definidas localizadas no diretório `configs/`.

Este design permite:
- Alternar rapidamente entre diferentes topologias
- Manter múltiplas configurações versionadas
- Criar configurações personalizadas sem modificar o código base
- Garantir que o cluster seja sempre provisionado conforme a configuração ativa

## Configurações Pré-definidas

O projeto fornece três configurações prontas para uso:

### 1. Nano (`configs/hosts-nano.yml`)

**Uso recomendado:** Testes rápidos e ambientes com recursos muito limitados

**Topologia:**
- 1 Load Balancer
- 1 Manager Node
- 1 Worker Node
- 1 Servidor NFS
- 1 Bastion Host (kubox)

**Recursos aproximados:** ~6GB RAM, 6 vCPUs

**Cenários ideais:**
- Primeiros testes com o projeto
- Ambiente de desenvolvimento pessoal
- Máquinas com recursos limitados
- Validação rápida de conceitos

### 2. Mini (`configs/hosts-mini.yml`) - Padrão

**Uso recomendado:** Uso geral e estudos

**Topologia:**
- 1 Load Balancer
- 1 Manager Node
- 2 Worker Nodes
- 1 Servidor NFS
- 1 Bastion Host (kubox)

**Recursos aproximados:** ~10GB RAM, 9 vCPUs

**Cenários ideais:**
- Estudos de Kubernetes
- Testes de aplicações multi-pod
- Balanceamento básico de carga
- Configuração padrão do projeto

### 3. Completo (`configs/hosts-completo.yml`)

**Uso recomendado:** Alta disponibilidade e testes avançados

**Topologia:**
- 2 Load Balancers (HA com Keepalived)
- 3 Manager Nodes (quorum etcd)
- 2 Worker Nodes
- 1 Servidor NFS
- 1 Bastion Host (kubox)

**Recursos aproximados:** ~19GB RAM, 18 vCPUs

**Cenários ideais:**
- Simulação de ambiente de produção
- Testes de alta disponibilidade
- Validação de failover
- Estudos avançados de Kubernetes
- Testes de conformidade (sonobuoy)

## Gerenciamento de Configurações

### Comandos Disponíveis

O Makefile fornece comandos específicos para gerenciar configurações:

#### Ativar uma Configuração

```bash
CLUSTER=<tipo> make init
```

Onde `<tipo>` pode ser: `nano`, `mini` ou `completo`.

**Exemplos:**
```bash
# Ativar configuração mínima
CLUSTER=nano make init

# Ativar configuração padrão
CLUSTER=mini make init

# Ativar configuração completa
CLUSTER=completo make init
```

#### Verificar Configuração Ativa

```bash
make status
```

Este comando mostra qual configuração está atualmente ativa através do symlink `inventario/hosts.yml`.

#### Visualizar Ajuda

```bash
make help
```

Exibe todos os comandos disponíveis e uma breve explicação do sistema de configurações.

### Fluxo de Trabalho Típico

1. **Escolher a configuração apropriada:**
   ```bash
   CLUSTER=mini make init
   ```

2. **Verificar a configuração ativa:**
   ```bash
   make status
   ```

3. **Provisionar o cluster:**
   ```bash
   make k8s-in-a-box
   ```

4. **Alternar para outra configuração (se necessário):**
   ```bash
   # Primeiro destruir o cluster atual
   make destroy
   
   # Ativar nova configuração
   CLUSTER=completo make init
   
   # Provisionar com a nova configuração
   make k8s-in-a-box
   ```

## Configuração Padrão

Se você **não executar** `make init` antes de provisionar o cluster, o projeto utilizará automaticamente a configuração **`mini`** como padrão. Isso garante que o projeto funcione "out of the box" sem configuração manual.

## Criando Configurações Personalizadas

Você pode criar suas próprias configurações seguindo o padrão dos arquivos existentes:

1. **Criar novo arquivo de configuração:**
   ```bash
   cp configs/hosts-mini.yml configs/hosts-minha-config.yml
   ```

2. **Editar o arquivo conforme suas necessidades:**
   - Ajustar IPs, memória e CPUs
   - Adicionar ou remover nós
   - Modificar FQDNs

3. **Ativar a configuração personalizada:**
   ```bash
   CLUSTER=minha-config make init
   ```

### Estrutura do Arquivo de Configuração

Cada arquivo de configuração (`configs/hosts-*.yml`) segue a estrutura padrão do inventário Ansible:

```yaml
all:
  vars:
    ansible_user: vagrant

  children:
    loadbalancers:
      hosts:
        loadbalancer1:
          ansible_host: 172.24.0.21
          fqdn: loadbalancer1.k8sbox.local
          memory: 512
          cpus: 1
    
    managers:
      hosts:
        manager1:
          ansible_host: 172.24.0.31
          fqdn: manager1.k8sbox.local
          memory: 3072
          cpus: 2
    
    workers:
      hosts:
        worker1:
          ansible_host: 172.24.0.41
          fqdn: worker1.k8sbox.local
          memory: 3072
          cpus: 2
    # ... outros grupos
```

**Campos importantes:**
- `ansible_host`: IP da VM na rede privada (172.24.0.0/24)
- `fqdn`: Nome completo da máquina (usado no `/etc/hosts`)
- `memory`: Memória RAM em MB
- `cpus`: Número de vCPUs

## Considerações Importantes

### Recursos do Host

Certifique-se de que sua máquina host possui recursos suficientes antes de escolher uma configuração:

- **CPU:** Verifique o total de vCPUs necessário
- **RAM:** Considere deixar margem para o sistema operacional host
- **Disco:** O projeto requer espaço para VMs, imagens e artefatos

### Compatibilidade de Rede

Todas as configurações utilizam a mesma faixa de rede (`172.24.0.0/24`). Se você precisar alterar a rede:

1. Editar o arquivo de configuração em `configs/`
2. Editar `inventario/group_vars/all.yml` (variável `rede_cidr_hosts`)
3. Ajustar o `Vagrantfile` se necessário

### Migração Entre Configurações

**Importante:** Não é possível migrar um cluster ativo entre configurações. Para mudar de configuração:

1. Fazer backup dos dados importantes (se houver)
2. Destruir o cluster atual (`make destroy`)
3. Ativar a nova configuração (`CLUSTER=nova make init`)
4. Provisionar novamente (`make k8s-in-a-box`)

### Versionamento

O arquivo `inventario/hosts.yml` está listado no `.gitignore` e **não é commitado** no Git, pois é gerado dinamicamente. Apenas os arquivos em `configs/hosts-*.yml` devem ser versionados.

## Troubleshooting

### Erro: "Nenhuma configuração ativa"

Se você executar comandos do Makefile sem ter ativado uma configuração, verá esta mensagem. O projeto automaticamente ativará a configuração padrão (`mini`).

**Solução:** Execute `make init` com a configuração desejada.

### Symlink Não Existe

Se o symlink `inventario/hosts.yml` não existir, ele será criado automaticamente na primeira execução de `make k8s-in-a-box` ou qualquer outro target que use `garante-config`.

### Configuração Errada Ativa

Para verificar qual configuração está ativa:
```bash
make status
```

Para mudar:
```bash
CLUSTER=nova-config make init
```

## Resumo de Comandos

| Comando | Descrição |
|---------|-----------|
| `CLUSTER=<tipo> make init` | Ativa uma configuração específica |
| `make status` | Mostra a configuração ativa |
| `make help` | Exibe ajuda completa do Makefile |
| `make k8s-in-a-box` | Provisiona o cluster com a configuração ativa |
| `make destroy` | Destroi o cluster atual |

---

**Nota:** Este sistema de configurações foi projetado para melhorar a flexibilidade mantendo a simplicidade, considerando os addons que foram adicionados no projeto. Para uso avançado, considere criar suas próprias configurações personalizadas baseadas nos exemplos fornecidos.