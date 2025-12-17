# Estrutura de PKI

Em um cluster Kubernetes construído manualmente, a segurança da comunicação entre componentes é fundamental. O **k8s‑in‑a‑box** implementa uma infraestrutura de chaves públicas (PKI) completa e hierárquica, onde todos os componentes críticos utilizam certificados digitais para autenticação mútua e criptografia via mTLS.

Ao contrário de ferramentas como `kubeadm` que geram certificados de forma opaca, esta implementação expõe toda a estrutura de certificação, permitindo entender exatamente como cada certificado é criado, quem o assina, para que serve e onde é utilizado. Este documento detalha toda a arquitetura de certificados do cluster, desde a autoridade certificadora raiz até os certificados individuais de cada nó.

## O que é PKI?

Uma **Infraestrutura de Chaves Públicas (PKI)** é um conjunto de políticas, procedimentos e tecnologias para criar, gerenciar, distribuir e validar certificados digitais. No contexto do Kubernetes, a PKI estabelece relações de confiança entre componentes através de certificados X.509 assinados por Autoridades Certificadoras (CAs).

### Componentes de uma PKI

* **Root CA (Autoridade Certificadora Raiz):** certificado autoassinado que está no topo da hierarquia de confiança. É usado para assinar CAs intermediários e deve ser protegido rigorosamente, idealmente mantido offline após a geração inicial.

* **Intermediate CA (CA Intermediário):** certificado assinado pela Root CA, responsável por assinar os certificados finais (end-entity). Esta camada adicional permite segmentação de responsabilidades e facilita revogação caso necessário, sem comprometer toda a PKI.

* **End-entity Certificates (Certificados Finais):** certificados de servidores e clientes assinados por CAs intermediários, usados efetivamente pelos componentes do cluster para provar identidade e estabelecer comunicação segura.

* **Subject Alternative Names (SANs):** extensão X.509 que permite incluir múltiplos nomes DNS e endereços IP em um certificado. Essencial para serviços acessíveis por diferentes hostnames ou IPs, como o kube-apiserver que pode ser acessado via IP do nó, VIP do load balancer ou nome de serviço interno.

## Hierarquia de CAs

O **k8s‑in‑a‑box** implementa uma hierarquia de três CAs intermediários, cada um especializado em um subsistema do cluster:

```
Root CA (k8sbox-root-ca)
├── Intermediate CA: etcd
│   ├── Certificados de servidor etcd (um por nó manager)
│   ├── Certificados de peer etcd (um por nó manager)
│   └── Certificados de cliente etcd (etcd-cli, kube-apiserver-etcd-client)
├── Intermediate CA: kubernetes
│   ├── Certificados de servidor kube-apiserver (um por nó manager)
│   ├── Certificados de cliente kube-apiserver-kubelet-client
│   ├── Certificados de cliente kube-controller-manager
│   ├── Certificados de cliente kube-scheduler
│   ├── Certificados de servidor/cliente kubelet (um por nó)
│   ├── Certificados de cliente kube-proxy
│   ├── Certificados de cliente admin
│   └── Certificados de service account
└── Intermediate CA: front-proxy
    └── Certificados de cliente front-proxy
```

Esta segmentação oferece vários benefícios práticos:

* **Isolamento de responsabilidades:** cada subsistema possui seu próprio CA intermediário, facilitando auditoria e gestão independente
* **Segurança aprimorada:** o comprometimento de um CA intermediário expõe apenas seu subsistema, não toda a PKI
* **Rotação facilitada:** CAs intermediários podem ser renovados sem afetar a Root CA ou outros subsistemas
* **Conformidade:** estrutura alinhada com as melhores práticas de PKI empresarial

## Processo de Geração de Certificados

A criação de um certificado digital segue quatro etapas fundamentais, todas automatizadas através do Ansible. Entender este fluxo é importante para diagnosticar problemas e realizar rotações manuais quando necessário.

### 1. Geração do Par de Chaves (Pública/Privada)

O processo começa com a criação de um par de chaves criptográficas usando ECDSA com a curva secp256r1:

```yaml
community.crypto.openssl_privatekey:
  path: /caminho/para/chave-priv.pem
  type: ECC
  curve: secp256r1
```

A **chave privada** é mantida em segredo absoluto e nunca deve ser compartilhada. A **chave pública** correspondente é derivada matematicamente da privada e será incorporada no certificado final. Este par de chaves é a base criptográfica de toda a autenticação.

### 2. Criação do Certificate Signing Request (CSR)

O CSR é uma solicitação formal de certificado que contém todas as informações necessárias para identificar o solicitante e definir os usos permitidos do certificado:

* **Subject (DN):** identidade do solicitante através do Common Name (CN), Organization (O) e outros atributos
* **Chave pública:** extraída do par de chaves gerado anteriormente
* **Extensões X.509:** atributos especiais como Key Usage, Extended Key Usage e SANs que definem como o certificado pode ser usado
* **Assinatura:** o CSR é assinado pela chave privada do solicitante para provar posse da chave

Exemplo de CSR para etcd-server:

```yaml
community.crypto.openssl_csr_pipe:
  privatekey_path: /caminho/para/chave-priv.pem
  digest: sha256
  subject:
    CN: "etcd-node-manager01-server"
  basic_constraints:
    - "CA:FALSE"                    # Não é uma CA
  key_usage:
    - digitalSignature               # Pode assinar dados
  extended_key_usage:
    - serverAuth                     # Certificado de servidor
    - clientAuth                     # Certificado de cliente (mTLS)
  subject_alt_name:
    - "DNS:manager01"
    - "IP:172.24.0.31"
    - "DNS:etcd.k8sbox.local"
    - "IP:172.24.0.10"
```

Os campos `key_usage` e `extended_key_usage` são críticos pois definem **para que o certificado pode ser usado**. Servidores requerem `serverAuth`, clientes requerem `clientAuth`, e em conexões mTLS (como etcd) ambos são necessários.

### 3. Assinatura pelo CA (Certificate Authority)

O CA recebe o CSR e, após validação, emite o certificado:

1. Extrai a chave pública e atributos do CSR
2. Cria um certificado X.509 incorporando essas informações
3. Adiciona metadata próprio (validade, número de série, emissor)
4. **Assina o certificado com sua própria chave privada**

```yaml
community.crypto.x509_certificate:
  path: /caminho/para/certificado-cert.pem
  csr_content: "{{ conteudo_do_csr }}"
  provider: ownca
  ownca_path: /caminho/para/ca-cert.pem         # Certificado do CA
  ownca_privatekey_path: /caminho/para/ca-priv.pem  # Chave privada do CA
  ownca_not_after: "+30d"                       # Validade de 30 dias
```

A assinatura do CA é a **garantia de autenticidade** do certificado. Qualquer um pode verificar a assinatura usando a chave pública do CA (presente em `ca-cert.pem`) e ter certeza de que aquele certificado foi realmente emitido por aquela autoridade.

### 4. Distribuição e Cadeia de Confiança

Após assinado, o certificado final contém todos os elementos necessários para uso: chave pública, identidade, extensões, informações do emissor, período de validade e assinatura digital do CA. Este certificado é então distribuído para os nós do cluster onde será usado junto com sua chave privada correspondente.

Quando um componente apresenta seu certificado, o receptor executa a seguinte validação:

1. Extrai o certificado apresentado
2. Verifica a assinatura usando o certificado do CA intermediário
3. Verifica a assinatura do CA intermediário usando o certificado da Root CA
4. Se todas as assinaturas forem válidas e a Root CA for confiável, o certificado é aceito

Esta é a **cadeia de certificação**, e por isso todos os componentes precisam ter não apenas o certificado do CA intermediário, mas toda a cadeia até a Root CA. O Ansible cuida de distribuir estes arquivos de cadeia (ca-chain.pem) para todos os nós.

## Validades e Planejamento de Rotação

A definição das validades dos certificados segue uma estratégia de prazos curtos para fins educacionais:

| Tipo | Duração | Justificativa |
|------|---------|---------------|
| Root CA | 1825 dias (5 anos) | Minimiza operações críticas de renovação da raiz |
| Intermediate CAs | 365 dias (1 ano) | Permite múltiplas rotações de certificados finais |
| End-entity | 30 dias (1 mês) | Cria ambiente de aprendizado com ciclos frequentes |
| Alerta | 7 dias | Notificação antes da expiração |

Esta proporção de **1:12:60** (certificados finais : CAs intermediários : Root CA) foi escolhida especificamente para criar um **ambiente de aprendizado realista**. Em ambientes de produção tradicionais, certificados costumam ter validades de 1-2 anos, o que significa que você pode passar anos sem precisar lidar com rotações. 

No **k8s‑in‑a‑box**, as validades curtas permitem:

* **Ciclo de aprendizado acelerado:** em apenas 30 dias você vivencia um ciclo completo de rotação
* **Prática frequente:** múltiplas oportunidades de executar e aperfeiçoar procedimentos de renovação
* **Simulação realista:** preparação para ambientes modernos de alta segurança que adotam certificados de curta duração (como Let's Encrypt)
* **Desenvolvimento de automação:** necessidade de criar scripts e processos automatizados, habilidade essencial para operações de Kubernetes

### Rotações Futuras

Este documento apresenta a estrutura de PKI, mas não cobre procedimentos operacionais detalhados. Em documentações futuras serão fornecidos guias completos sobre:

* **Rotação de certificados finais:** processo mensal automatizado, incluindo scripts, validações e rollback
* **Rotação de CAs intermediários:** procedimento anual com período de dupla confiança, permitindo transição gradual sem downtime
* **Rotação da Root CA:** operação crítica quinquenal que envolve troca completa da cadeia de confiança, planejada para execução sem interrupção do cluster

## Especificação de Certificados

A tabela abaixo lista todos os certificados gerados para o cluster, seguindo as recomendações da [documentação oficial do Kubernetes sobre PKI](https://kubernetes.io/docs/setup/best-practices/certificates/).

### Autoridades Certificadoras

| Path | Default CN | Descrição | Validade |
|------|-----------|-----------|----------|
| `pki/root-ca.crt`, `root-ca.key` | k8sbox-root-ca | Root CA do cluster | 1825 dias (5 anos) |
| `pki/etcd/ca.crt`, `ca.key` | k8sbox-etcd-ca | CA intermediário para componentes etcd | 365 dias (1 ano) |
| `pki/kubernetes/ca.crt`, `ca.key` | k8sbox-kubernetes-ca | CA intermediário para componentes Kubernetes | 365 dias (1 ano) |
| `pki/front-proxy/ca.crt`, `ca.key` | k8sbox-front-proxy-ca | CA intermediário para front-proxy | 365 dias (1 ano) |

### Certificados de Servidor e Cliente

| Default CN | Parent CA | O (in Subject) | kind | hosts (SAN) | Validade |
|-----------|-----------|----------------|------|-------------|----------|
| `etcd-node-<hostname>-server` | etcd-ca | | server, client | `<hostname>`, `<Host_IP>`, `<VIP>`, `<VIP_FQDN>`, `localhost`, `127.0.0.1` | 30 dias |
| `etcd-node-<hostname>-peer` | etcd-ca | | server, client | `<hostname>`, `<Host_IP>`, `localhost`, `127.0.0.1` | 30 dias |
| `etcd-cli-client` | etcd-ca | | client | | 30 dias |
| `kube-apiserver` | kubernetes-ca | | server | `<hostname>`, `<Host_IP>`, `<VIP>`, `<VIP_FQDN>`, `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`, `<Service_IP>`, `localhost`, `127.0.0.1` | 30 dias |
| `kube-apiserver-etcd-client` | etcd-ca | | client | | 30 dias |
| `kube-apiserver-kubelet-client` | kubernetes-ca | system:masters | client | | 30 dias |
| `system:kube-controller-manager` | kubernetes-ca | | client | | 30 dias |
| `system:kube-scheduler` | kubernetes-ca | | client | | 30 dias |
| `system:kube-proxy` | kubernetes-ca | | client | | 30 dias |
| `system:node:<nodeName>` | kubernetes-ca | system:nodes | server, client | `<hostname>`, `<Host_IP>`, `localhost`, `127.0.0.1` | 30 dias |
| `admin` | kubernetes-ca | system:masters | client | | 30 dias |
| `front-proxy-client` | front-proxy-ca | | client | | 30 dias |

**Notas:**

- **`kind`** mapeia para x509 key usage:
  - **server:** digital signature, key encipherment, server auth
  - **client:** digital signature, key encipherment, client auth

- **Certificados individualizados por nó:** os certificados marcados com `<hostname>` são gerados individualmente para cada nó do cluster (etcd-server, etcd-peer, kube-apiserver, kubelet), seguindo o princípio de menor privilégio.

- **SANs (Subject Alternative Names):** `<VIP>` refere-se ao IP virtual do Keepalived (`172.24.0.10`), `<VIP_FQDN>` aos FQDNs configurados (`api.k8sbox.local`, `etcd.k8sbox.local`), e `<Service_IP>` ao primeiro IP do CIDR de serviços.

- **Validades configuráveis:** todos os prazos são configuráveis através das variáveis em `ansible/01-pki/defaults/main.yml` na seção `pki_validade`.

### Par de Chaves de Service Account

| Private key path | Public key path | Descrição | Validade |
|-----------------|-----------------|-----------|----------|
| `pki/sa.key` | `pki/sa.pub` | Par de chaves RSA para assinatura de tokens JWT de service accounts | 365 dias (1 ano) |

Embora não seja tecnicamente um certificado X.509, este par de chaves é usado pelo kube-apiserver para verificar tokens e pelo kube-controller-manager para gerar tokens de service accounts, permitindo que pods se autentiquem junto ao API Server.

## Certificados Individualizados por Nó

Uma decisão importante no **k8s‑in‑a‑box** foi a geração de **certificados individuais por nó** para componentes que executam em múltiplos hosts. Seria mais simples gerar um único certificado compartilhado, mas esta abordagem oferece vantagens significativas:

* **Princípio do menor privilégio:** cada nó possui apenas os certificados necessários para sua função específica
* **Auditoria granular:** é possível rastrear qual nó realizou determinada operação através do certificado apresentado
* **Segurança aprimorada:** comprometimento de um nó não expõe certificados de outros nós
* **Revogação seletiva:** possibilidade de revogar certificado de um nó específico sem afetar o restante do cluster
* **Rotação facilitada:** certificados podem ser rotacionados individualmente sem downtime do cluster

**Componentes com certificados individualizados:**

* **etcd-server:** um certificado por nó manager, com SANs específicos do nó + VIP
* **etcd-peer:** um certificado por nó manager, com SANs apenas do próprio nó
* **kube-apiserver:** um certificado por nó manager, com SANs do nó + VIP + serviços internos
* **kubelet:** um certificado por nó (managers e workers), com SANs do próprio nó e CN no formato `system:node:<hostname>`

## Detalhamento dos Certificados

### Certificados do etcd

O etcd é o banco de dados distribuído do Kubernetes e requer três tipos de certificados para operação segura:

#### etcd-server

* **Finalidade:** autenticar o servidor etcd para clientes (como kube-apiserver)
* **Extended Key Usage:** `serverAuth`, `clientAuth`
* **SANs incluídos:** IP e FQDN do próprio nó manager, IP e FQDN do VIP, localhost

O certificado inclui o VIP para que clientes possam se conectar tanto diretamente ao nó quanto através do HAProxy sem erro de validação de certificado. Isto é essencial para alta disponibilidade.

#### etcd-peer

* **Finalidade:** autenticar comunicação entre membros do cluster etcd (Raft protocol)
* **Extended Key Usage:** `serverAuth`, `clientAuth`
* **SANs incluídos:** IP e FQDN do próprio nó manager, localhost

Certificado simplificado que inclui apenas o próprio nó, pois a comunicação peer-to-peer é direta entre nós específicos, sem passar pelo load balancer.

#### etcd-cli

* **Finalidade:** permitir administração do etcd via etcdctl
* **Extended Key Usage:** `clientAuth`
* **CN:** etcd-cli-client
* **Instalado em:** bastion host (kubox)

Certificado de cliente genérico para operações administrativas, sem SANs pois não atua como servidor.

### Certificados do Kubernetes API Server

O kube-apiserver é o ponto central de comunicação do cluster e requer múltiplos certificados:

#### kube-apiserver (servidor)

* **Finalidade:** autenticar o API Server para clientes (kubectl, kubelet, controller-manager, scheduler)
* **Extended Key Usage:** `serverAuth`
* **SANs incluídos:**
  * IP e FQDN do próprio nó manager
  * IP e FQDN do VIP (api.k8sbox.local)
  * Nomes de serviço Kubernetes internos: `kubernetes`, `kubernetes.default`, `kubernetes.default.svc`, `kubernetes.default.svc.cluster.local`
  * IP do serviço Kubernetes (primeiro IP do CIDR de serviços)
  * localhost

Este conjunto abrangente de SANs suporta acesso via múltiplas formas: direto, load balancer e nome de serviço interno, garantindo que pods possam comunicar com o API Server através do serviço `kubernetes.default`.

#### kube-apiserver-etcd-client

* **Finalidade:** autenticar o API Server como cliente do etcd
* **Extended Key Usage:** `clientAuth`
* **CN:** kube-apiserver-etcd-client

O API Server precisa de credenciais de cliente para ler/escrever no etcd. Note que este certificado é assinado pelo **etcd-ca**, não pelo kubernetes-ca, refletindo o uso cross-subsystem.

#### kube-apiserver-kubelet-client

* **Finalidade:** autenticar o API Server ao se comunicar com kubelets (para logs, exec, port-forward)
* **Extended Key Usage:** `clientAuth`
* **CN:** kube-apiserver-kubelet-client
* **Organization:** system:masters

O API Server atua como cliente ao requisitar operações nos kubelets. A organização `system:masters` garante permissões administrativas via RBAC.

### Certificados dos Componentes do Control Plane

#### kube-controller-manager

* **Finalidade:** autenticar o controller-manager junto ao API Server
* **Extended Key Usage:** `clientAuth`
* **CN:** system:kube-controller-manager

O controller-manager gerencia recursos do cluster e precisa de permissões amplas, concedidas via RBAC ao usuário `system:kube-controller-manager`.

#### kube-scheduler

* **Finalidade:** autenticar o scheduler junto ao API Server
* **Extended Key Usage:** `clientAuth`
* **CN:** system:kube-scheduler

O scheduler decide onde executar pods e precisa de acesso de leitura a recursos de nós e pods, concedido via RBAC.

#### kube-proxy

* **Finalidade:** autenticar o kube-proxy junto ao API Server
* **Extended Key Usage:** `clientAuth`
* **CN:** system:kube-proxy

O kube-proxy gerencia regras de iptables/ipvs para roteamento de serviços e precisa de acesso de leitura a endpoints e serviços.

### Certificados do Kubelet

#### kubelet (servidor/cliente)

* **Finalidade:** autenticar o kubelet tanto como servidor (para kube-apiserver) quanto como cliente (ao se registrar no cluster)
* **Extended Key Usage:** `serverAuth`, `clientAuth`
* **CN:** `system:node:<hostname>` (ex: system:node:manager01)
* **Organization:** system:nodes
* **SANs incluídos:** IP e FQDN do próprio nó, localhost

O CN no formato `system:node:<hostname>` é exigido pelo Kubernetes para Node Authorization. A organization `system:nodes` concede permissões via RBAC para o kubelet gerenciar recursos do próprio nó.

### Certificados de Administração

#### admin

* **Finalidade:** autenticar usuários administrativos junto ao API Server
* **Extended Key Usage:** `clientAuth`
* **CN:** admin
* **Organization:** system:masters

A organização `system:masters` é mapeada para o ClusterRole `cluster-admin` via RBAC, concedendo permissões administrativas completas no cluster. Este certificado é usado pelo kubectl configurado no kubox.

## Algoritmos e Parâmetros Criptográficos

O **k8s‑in‑a‑box** utiliza algoritmos modernos e seguros para geração de certificados:

* **Algoritmo de chave:** ECDSA (Elliptic Curve Digital Signature Algorithm)
* **Curva elíptica:** secp256r1 (NIST P-256)
* **Algoritmo de hash:** SHA-256

### Justificativa da Escolha

**ECDSA** oferece segurança equivalente a RSA com chaves menores (256 bits ECDSA ≈ 3072 bits RSA), resultando em menor consumo de CPU e largura de banda. A curva **secp256r1** (também conhecida como P-256) é amplamente suportada, oferece 128 bits de segurança e é adequada para uso geral. **SHA-256** é resistente a colisões e adequado para o tamanho da curva escolhida.

Estes parâmetros são configuráveis em `ansible/01-pki/defaults/main.yml`:

```yaml
pki_cifra_tipo: "ECC"
pki_cifra_algo: "secp256r1"
pki_algoritmo_hash: "sha256"
```

## Processo de Geração e Distribuição

O processo de geração e distribuição de certificados é totalmente automatizado via Ansible, executando em duas fases distintas:

### Fase 1: Geração Local

Toda a geração de certificados ocorre no host de controle Ansible (delegated to localhost), nunca nos nós do cluster:

1. **Root CA:** gerada e autoassinada
2. **Intermediate CAs:** gerados e assinados pela Root CA
3. **Certificados finais:** gerados e assinados pelos respectivos CAs intermediários
4. **Verificações:** Ansible verifica existência de arquivos para evitar regeneração desnecessária (idempotência)

### Fase 2: Distribuição

Após geração, os certificados são distribuídos seletivamente:

1. **Cópia seletiva:** apenas os certificados necessários são copiados para cada nó
2. **Permissões:** chaves privadas recebem permissão `0600`, certificados públicos `0644`
3. **Propriedade:** arquivos pertencem aos usuários dos serviços correspondentes
4. **Cadeias de certificados:** Root CA e CAs intermediários são combinados em arquivos de cadeia (ca-chain.pem) para validação

### Segurança no Processo

* **Chaves privadas nunca transitam pela rede:** todas são geradas localmente no host Ansible
* **Distribuição seletiva:** cada nó recebe apenas suas próprias chaves privadas, nunca as de outros nós
* **Root CA offline:** após geração inicial, pode ser removida do host Ansible e armazenada offline em local seguro
* **Idempotência:** execução repetida do playbook não regenera certificados existentes, a menos que `pki_regerar_certs: true`

## Validação dos Certificados

Após a geração, é possível validar os certificados utilizando ferramentas OpenSSL:

```bash
# Verificar informações de um certificado
openssl x509 -in certificado.pem -text -noout

# Verificar cadeia de certificação
openssl verify -CAfile ca-chain.pem certificado.pem

# Verificar SANs de um certificado
openssl x509 -in certificado.pem -text -noout | grep -A1 "Subject Alternative Name"

# Verificar conectividade mTLS (exemplo etcd)
openssl s_client -connect 172.24.0.31:2379 \
  -cert etcd-cli.pem \
  -key etcd-cli-key.pem \
  -CAfile ca-chain.pem
```

## Conformidade

O **k8s‑in‑a‑box** passou pelo teste de conformidade **Sonobuoy** da CNCF, que valida entre outras coisas a correta configuração de certificados e mTLS no cluster. Este teste garante que a implementação PKI segue os padrões esperados pelo ecossistema Kubernetes.

## Conclusão

A estrutura de PKI do **k8s‑in‑a‑box** representa uma implementação completa de autenticação e criptografia para um cluster Kubernetes. A hierarquia de CAs, certificados individualizados por nó, escolha de algoritmos modernos e automação completa via Ansible garantem um ambiente seguro e auditável.

Esta fundação de segurança permite que todos os demais componentes do cluster se comuniquem de forma autenticada e criptografada, protegendo dados sensíveis e prevenindo acessos não autorizados. Nos próximos documentos serão explorados em detalhes a configuração de cada componente que depende desta PKI.