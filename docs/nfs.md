# Servidor NFS e Armazenamento

Em ambientes Kubernetes locais ou de laboratório, gerenciar armazenamento persistente de forma flexível é essencial. O **k8s-in-a-box** soluciona isso dedicando um nó ao papel de **Servidor NFS (Network File System)**.

A automação deste provisionamento é guiada pela role Ansible `04-nfs`, e a integração com o cluster Kubernetes ocorre por meio do role `13-addons-cluster`.

## Configuração do Servidor

O objetivo principal deste nó é prover um sistema de arquivos via rede que o cluster possa montar dinamicamente.

### Instalação

A instalação básica envolve a adição do pacote `nfs-utils` no sistema operacional base (AlmaLinux). Este pacote contém todos os binários necessários para que a máquina possa exportar diretórios para outras através do protocolo NFS. O serviço principal gerenciado pelo Ansible é o `nfs-server`.

### Exportação de Diretórios

Para que o NFS funcione, é necessário configurar o arquivo `/etc/exports`, que dita quais diretórios locais podem ser acessados pela rede e com quais permissões.

* **Diretório Exportado:** O projeto cria e exporta o diretório base `/srv/nfs/k8s`.
* **Regras de Acesso:**
  * O acesso é liberado para toda a rede privada do cluster, ou seja, para o bloco `172.24.0.0/24` (definido por `rede_cidr_hosts`).
  * A opção `rw` garante leitura e escrita.
  * A opção `sync` assegura que as requisições ao disco sejam gravadas de forma confiável antes de enviar uma resposta de sucesso ao cliente.
  * O parâmetro `no_root_squash` permite que o cliente (no caso, o provisionador do Kubernetes) gerencie os arquivos e pastas criadas com permissão de superusuário dentro desse compartilhamento.

Quando as alterações são feitas, o Ansible invoca o comando `exportfs -arv` (ou reinicia o serviço) para aplicar as configurações.

## Consumo pelo Cluster (NFS Subdir External Provisioner)

Possuir apenas um servidor NFS na rede não é suficiente para a mágica do Kubernetes. É necessário um componente que ensine ao cluster como "fatiar" esse armazenamento quando um pod pedir disco.

O consumo acontece no cluster através do addon **NFS Subdir External Provisioner**.

### Como funciona a integração:

1. **StorageClass:** O provisioner cria uma StorageClass chamada `nfs-client` no Kubernetes, que é marcada como classe de armazenamento padrão.
2. **PersistentVolumeClaims (PVCs):** Quando você realiza o deploy de uma aplicação (como um banco de dados) que solicita um disco (PVC), ela utiliza a StorageClass `nfs-client`.
3. **Provisionamento Dinâmico:**
   * Em vez de você ter que entrar no nó NFS e criar uma pasta manualmente, o Provisioner intercepta o pedido do PVC.
   * Ele se conecta ao servidor NFS (`172.24.0.51`) utilizando o path exportado (`/srv/nfs/k8s`).
   * Cria subdiretórios automaticamente (com o nome no formato `namespace-pvcName-pvName`) dentro de `/srv/nfs/k8s`.
   * Monta esse subdiretório diretamente no Pod requisitante.

Graças a esta abstração, o cluster comporta-se de forma semelhante a provedores de nuvem pública (AWS, GCP), onde volumes persistentes são dinamicamente alocados sob demanda.
