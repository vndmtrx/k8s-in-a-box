# SELinux e Kubernetes
O **k8s-in-a-box** mantém o SELinux ativo em modo permissivo em todas as VMs do cluster. Diferentemente de muitos tutoriais e guias de instalação manual do Kubernetes que simplesmente desabilitam o SELinux, este projeto optou por mantê-lo ativo e desenvolver uma política customizada de Type Enforcement que resolve todos os alertas de segurança (AVCs) gerados pela operação normal do cluster.

Esta página documenta as decisões de segurança tomadas, a estrutura da política customizada e como ela interage com os diferentes componentes do Kubernetes.

## Por que manter o SELinux ativo?

A maioria dos guias de instalação manual do Kubernetes orienta a desativação do SELinux como um dos primeiros passos. Essa decisão, embora simplifique a instalação, remove uma camada de proteção importante no nível do kernel do sistema operacional.

No contexto do **k8s-in-a-box**, o SELinux serve como:

* **Camada de confinamento para containers**: limita o que os processos dentro de um container podem acessar no host, mesmo que consigam escapar das restrições do namespace Linux.
* **Proteção contra acessos indevidos a caminhos criticos do host**: como `/var/lib/etcd` (banco de dados do cluster), `/sys/fs/cgroup` (limites de recursos) e `/proc/net` (pilha de rede).
* **Demonstração de boas praticas**: em ambientes de producao baseados em RHEL/AlmaLinux, o SELinux normalmente esta ativo. Mantê-lo no laboratório permite estudar e entender os ajustes necessarios.

> 💡 O SELinux esta configurado em modo **permissivo** (`selinux: permissive` na role `02-sistema`). Isso significa que ele registra violações nos logs de auditoria (AVCs) mas não bloqueia operações. A política customizada foi desenvolvida para que, ao mudar para modo **enforcing**, o cluster continue operando normalmente.

## Camadas de confinamento

No cluster, os processos operam em diferentes dominios (contextos) do SELinux, organizados em camadas:

* **Host (init_t)**: o systemd e os servicos nativos do sistema operacional.
* **Runtime de containers (unconfined_service_t)**: o containerd ou CRI-O, que gerencia o ciclo de vida dos containers. O kubelet também opera nesse dominio.
* **Containers de aplicação (container_t)**: todos os pods normais do cluster (CoreDNS, Traefik, Headlamp, aplicações do usuario, etc.).
* **Containers privilegiados (spc_t)**: pods de sistema que precisam de acesso direto aos recursos do host (Etcd, kube-proxy).
* **Arquivos do container (container_file_t)**: o sistema de arquivos interno (rootfs) de cada container, rotulado automaticamente pelo runtime.

Essa separação garante que, por exemplo, um container de aplicação (`container_t`) não consiga acessar os mesmos recursos que o Etcd (`spc_t`) ou o kubelet (`unconfined_service_t`), mesmo que todos rodem na mesma maquina.

## A política customizada (`k8s-custom-selinux`)

O projeto inclui um módulo de política de Type Enforcement compilado e carregado automaticamente pelo Ansible durante a configuração do kubelet (role `06-kubelet`, task `08-selinux.yml`).

O template da política esta em `ansible/06-kubelet/templates/k8s-custom-selinux.te.j2`.

### Pipeline de compilação

O Ansible executa os seguintes passos em cada nó do cluster:

1. Instala o pacote `checkpolicy` (compilador de políticas do SELinux)
2. Renderiza o template `.te.j2` para `/etc/selinux/local/k8s-custom-selinux.te`
3. Compila o módulo: `checkmodule -M -m -o (...).mod (...).te`
4. Empacota o módulo: `semodule_package -o (...).pp -m (...).mod`
5. Carrega no kernel: `semodule -i (...).pp`

A compilação só é executada quando o template muda ou quando o arquivo `.pp` compilado não existe, evitando retrabalho em execuções repetidas do Ansible.

### Estrutura do arquivo `.te`

O arquivo é dividido em duas partes:

**Bloco `require`**: declara todos os tipos, atributos e classes de permissão que já existem na política base do sistema (`targeted`) e que serão usados nas regras. Isso diz ao compilador que esses símbolos existem e serão resolvidos no carregamento. Os tipos são organizados em grupos semânticos:

* Tipos do sistema operacional (init_t, unconfined_service_t, sysfs_t, cgroup_t, proc_t, etc.)
* Tipos de confinamento de containers (container_t, container_file_t)
* Atributos e tipos de rede (node_t, port_type)
* Classes de permissão de arquivos, sockets, processos e BPF

**Regras `allow`**: as liberações propriamente ditas, organizadas por domínio de destino:

| Grupo de Regras | Domínio | O que Permite |
|-----------------|---------|---------------|
| Dispositivos virtuais | container_t -> container_file_t | Leitura/escrita em `/dev/null` mapeado no rootfs |
| sysfs | container_t -> sysfs_t | Leitura do status de Transparent Huge Pages |
| cgroups (Read-Only) | container_t -> cgroup_t | Leitura de limites de CPU/memória (runtimes Go/Java) |
| Rede TCP/UDP | container_t -> port_type, node_t, self | Bind em portas, conexões, shutdown |
| Netlink | container_t -> self | Consulta de tabelas de roteamento pelo CNI |
| NFS | container_t -> nfs_t | Leitura/escrita em volumes persistentes montados via rede |
| procfs/nsfs | container_t -> proc_net_t, nsfs_t | Inspeção da pilha de rede e namespaces |
| var_lib (Read-Only) | container_t -> var_lib_t | Leitura de bibliotecas do overlayfs em `/var/lib/containerd` |
| Capabilities | container_t -> self | net_bind_service, dac_override, chown, setgid, setuid, kill |
| Transição de processos | unconfined_service_t -> container_t | Transição segura do runtime para o container (nnp_transition) |
| eBPF | init_t -> unconfined_service_t | Execução de programas eBPF pelo systemd |

### Decisão de hardening: acesso Read-Only a `var_lib_t` e `cgroup_t`

Duas decisões de segurança importantes foram tomadas nesta política:

1. **cgroup_t (cgroups do host)**: containers de aplicação podem apenas **ler** os limites de CPU e memória em `/sys/fs/cgroup`. Isso é necessario porque runtimes modernos (Go, Java) leem esses arquivos para dimensionar automaticamente threads e memória. A **escrita** foi removida, impedindo que aplicações alterem limites de recursos no host.

2. **var_lib_t (arquivos em `/var/lib`)**: containers podem apenas **ler** arquivos rotulados com `var_lib_t`. Isso resolve o caso em que o runtime de containers (overlayfs) não finaliza a reetiquetagem das camadas da imagem a tempo, e o processo dentro do container tenta carregar bibliotecas dinâmicas (como `ld-musl-x86_64.so.1` ou `libc.so.6`) que ainda estão sob o rótulo do host. A **escrita** foi removida, impedindo que containers de aplicação gravem em caminhos criticos como `/var/lib/etcd`.

Componentes de sistema que precisam de acesso de **escrita** a esses recursos (como o Etcd, que grava em `/var/lib/etcd`) rodam com `securityContext.privileged: true` no manifesto do Kubernetes, o que faz o runtime executá-los sob o domínio `spc_t` (Super Privileged Container), que não é confinado pelo SELinux.

## O kubelet e seu contexto SELinux

O kubelet é um caso especial. Ele não roda como container, mas como um serviço systemd direto no host. Suas configurações de SELinux são:

* **Binário**: instalado em `/usr/local/bin/kubelet` com o rótulo `bin_t` (via `setype: bin_t` na task do Ansible). Isso garante que o systemd reconheça o binário como um executável legítimo.
* **Contexto de execução**: o unit file do systemd inclui a diretiva `SELinuxContext=system_u:system_r:unconfined_service_t:s0`, que força o kubelet a rodar no domínio `unconfined_service_t`. Esse domínio tem acesso amplo aos recursos do host, necessario porque o kubelet precisa gerenciar containers, montar volumes, configurar rede e interagir com o runtime.

### Plugins de CNI

Os plugins de rede (CNI) são binários instalados em `/opt/cni/bin`. Após a instalação, o Ansible executa `restorecon -R /opt/cni/bin` para restaurar os rótulos de SELinux corretos nos binários, garantindo que o kubelet consiga executá-los sem alertas.

## Componentes do Control Plane em Modo Pod

Os componentes do Control Plane do cluster são executados como contêineres (Static Pods) gerenciados pelo Kubelet:

* **Etcd (Static Pod privilegiado - `spc_t`)**: Como o etcd precisa gravar diretamente no diretório do host `/var/lib/etcd` (que possui o rótulo genérico `var_lib_t`), seu manifesto é configurado com `privileged: true`. Isso faz com que o runtime de contêiner execute o etcd sob o domínio `spc_t` (Super Privileged Container), que não possui restrições de escrita no host.
* **kube-apiserver, kube-controller-manager e kube-scheduler (Static Pods - `container_t`)**: Esses componentes rodam como contêineres normais, mas com privilégios específicos e privilégio de rede do host (`hostNetwork: true`). Eles montam diretórios de configuração do host em `/etc/kubernetes/conf/<componente>`, os quais são montados como `readOnly: true` (ou `readWrite` no caso de caminhos de PKI específicos) e contam com o confinamento padrão do SELinux.
* **kube-proxy (DaemonSet - `spc_t`)**: Executa em todos os nós com `privileged: true` para poder manipular as tabelas de roteamento, iptables/IPVS e namespaces de rede do host.

## Verificação e troubleshooting

### Comandos úteis

Verificar se o modulo esta carregado:
```bash
semodule -l | grep k8s-custom-selinux
```

Consultar alertas de SELinux (AVCs) recentes:
```bash
ausearch -m avc -ts recent
```

Verificar o rótulo de um arquivo:
```bash
ls -Z /usr/local/bin/kubelet
# system_u:object_r:bin_t:s0 /usr/local/bin/kubelet
```

Verificar o contexto de um processo:
```bash
ps -eZ | grep kubelet
# system_u:system_r:unconfined_service_t:s0  14934 ?  00:00:06 kubelet
```

### Interpretando logs AVC

Quando o SELinux nega (ou registra, em modo permissivo) uma operação, ele grava um log AVC no audit. Exemplo:

```
type=AVC msg=audit(...): avc: denied { read } for pid=15945 comm="coredns"
  name="cpu.max" dev="cgroup2"
  scontext=system_u:system_r:container_t:s0:c786,c889
  tcontext=system_u:object_r:cgroup_t:s0
  tclass=file permissive=1
```

Os campos mais importantes são:

* **denied { read }**: a operação que foi negada (neste caso, leitura)
* **comm="coredns"**: o nome do processo que tentou a operação
* **scontext=...container_t...**: o contexto de origem (quem tentou)
* **tcontext=...cgroup_t...**: o contexto de destino (o que foi acessado)
* **tclass=file**: a classe do objeto (arquivo, diretório, socket, etc.)
* **permissive=1**: indica que o SELinux está em modo permissivo (registrou mas não bloqueou)

Se aparecer um AVC que você não esperava, a informação do `scontext` e `tcontext` indica exatamente qual regra `allow` seria necessária para resolver.
