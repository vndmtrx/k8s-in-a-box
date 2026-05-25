# Aplicações de Exemplo e Segurança (Rootless & Popeye)

O **k8s-in-a-box** inclui duas aplicações de demonstração implantadas no namespace `exemplos` para validar o funcionamento do cluster (como o roteamento do Gateway API, a persistência de volumes dinâmicos via NFS e o agendamento de tarefas em segundo plano).

Para garantir que o laboratório simule práticas recomendadas de segurança de produção, ambas as aplicações foram configuradas de forma **rootless** (não-root). Isso permitiu alcançar uma pontuação de **Score A (100%) no Popeye**, sem erros (💥) ou avisos (😱).

## 🚀 As Aplicações de Exemplo

### 1. Hello App (`hello-app`)
* **Tecnologia**: Nginx (`nginx:1.29-alpine`).
* **Propósito**: Servir a página inicial do cluster (dashboard de informações sobre os serviços ativos e credenciais de acesso).
* **Manifestos**:
  * [01-hello-configmap.yml](../ansible/100-exemplos/files/hello/01-hello-configmap.yml)
  * [02-hello-deployment.yml](../ansible/100-exemplos/files/hello/02-hello-deployment.yml)
  * [08-hello-networkpolicies.yml](../ansible/100-exemplos/files/hello/08-hello-networkpolicies.yml)

### 2. Contador de Acessos (`contador`)
* **Tecnologia**: PHP/Apache (`php:8.5-apache`) + CronJob de apoio (`debian:stable`).
* **Propósito**: Demonstrar a persistência em volumes compartilhados (gravação/leitura no arquivo `contador.txt` e `ultimo.txt` a cada acesso e no arquivo `cron.txt` a cada execução do CronJob).
* **Manifestos**:
  * [02-contador-configmap.yml](../ansible/100-exemplos/files/contador/02-contador-configmap.yml)
  * [03-contador-deployment.yml](../ansible/100-exemplos/files/contador/03-contador-deployment.yml)
  * [06-contador-cronjob.yml](../ansible/100-exemplos/files/contador/06-contador-cronjob.yml)
  * [07-contador-networkpolicies.yml](../ansible/100-exemplos/files/contador/07-contador-networkpolicies.yml)

## 🔒 Arquitetura de Execução Rootless (Não-Root)

O principal risco de segurança em containers é executá-los como `root`. Se um invasor conseguir escapar do container, ele terá privilégios totais de `root` no nó hospedeiro. 

Para anular esse risco nas imagens oficiais (Nginx e PHP/Apache), as seguintes técnicas foram implementadas nos manifestos:

### 1. Redirecionamento de Portas Privilegiadas (Porta 80 -> 8080)
Usuários comuns no Linux não podem fazer *bind* em portas abaixo de `1024` (portas privilegiadas). Como as imagens oficiais escutam na porta `80`, foi injetada uma configuração customizada via ConfigMap para fazê-las escutar na porta `8080`:

* **Nginx (`default.conf`)**:
  ```nginx
  server {
      listen       8080;
      listen  [::]:8080;
      ...
  }
  ```
* **Apache (`ports.conf` e `000-default.conf`)**:
  ```apache
  Listen 8080
  <VirtualHost *:8080>
      ...
  </VirtualHost>
  ```

Essas configurações são aplicadas no Deployment usando `volumeMounts` com `subPath`, sobrepondo os arquivos de configuração originais dentro dos containers.

### 2. Configuração do `securityContext`
Tanto o Pod quanto o container são forçados a rodar sem privilégios:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101       # 101 é o UID do 'nginx' em Alpine / 10001 para o Apache/CronJob
  runAsGroup: 101      # GID correspondente
  fsGroup: 10001       # Crucial para volumes persistentes (veja abaixo)
```

### 3. Liberação de Pastas Temporárias (`emptyDir`)
Tanto o Apache quanto o Nginx gravam arquivos temporários (PIDs, caches, locks) em diretórios do sistema que pertencem ao `root`. Para que usuários não-root possam rodar esses serviços, criamos volumes temporários na memória (`emptyDir`) montados nas seguintes pastas:
* **Nginx**: `/var/run` e `/var/cache/nginx`.
* **Apache**: `/var/run/apache2` e `/var/lock/apache2`.

### 4. Preservação de Logs em `stdout` / `stderr`
As imagens oficiais utilizam links simbólicos em `/var/log/nginx` e `/var/log/apache2` apontando para `/dev/stdout` e `/dev/stderr`. **Evitamos** montar volumes `emptyDir` nesses caminhos de log para não deletar os links simbólicos. No caso do Apache, redirecionamos os caminhos explicitamente no ConfigMap:
```apache
ErrorLog /dev/stderr
CustomLog /dev/stdout combined
```
Isso mantém o `kubectl logs` funcionando perfeitamente.

### 5. Controle Nativo de Permissões com `fsGroup`
Para o volume de dados compartilhado (`contador-pvc`), em vez de usar containers de inicialização (`initContainers`) rodando como root para alterar permissões com `chmod`, foi configurado o `fsGroup: 10001` no Pod.

Isso instrui o Kubernetes a associar o GID `10001` aos processos que escrevem no volume, garantindo acesso nativo sem a necessidade de privilégios adicionais. Além disso, alinhamos o `runAsUser`/`runAsGroup` do `contador-cronjob` para `10001` para que tanto a aplicação web quanto o cronjob compartilhem a mesma identidade de gravação no volume compartilhado.

## 🐕 Validação e Conformidade com Popeye (Score 100% A)

O **Popeye** é um utilitário CLI que inspeciona clusters Kubernetes em tempo real e avalia se os recursos seguem as melhores práticas recomendadas de segurança, recursos e conformidade.

Ao rodar a verificação no namespace das aplicações prontas (`popeye -n exemplos`), o cluster atinge a pontuação máxima:

```text
Your cluster score: A (100)
                                                o          .-'-.
                                                 o     __| A    `\
                                                  o   `-,-`--._   `\
                                                 []  .->'  a     `|-'
                                                  `=/ (__/_       /
                                                    \_,    `    _)
                                                       `----;  |
```

### Critérios de Sucesso Avaliados:
* **Sem containers rodando como root**: Aprovado graças ao `runAsNonRoot: true` e portas `>= 1024`.
* **Configuração correta de Probes**: Os probes de `liveness` e `readiness` estão devidamente configurados apontando para a porta HTTP local correta.
* **Uso correto de recursos**: Limits e Requests de CPU/Memória estão definidos para evitar desperdício ou sobrecarga de nós.
* **Isolamento de Rede**: NetworkPolicies ativas restringem o tráfego de entrada e saída somente para o necessário (por exemplo, permitindo apenas tráfego oriundo do Gateway Traefik).
