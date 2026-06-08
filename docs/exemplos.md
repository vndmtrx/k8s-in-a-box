# Aplicações de Exemplo e Segurança (Rootless & Popeye)

O **k8s-in-a-box** inclui duas aplicações de demonstração implantadas no namespace `exemplos` para validar o funcionamento do cluster (como o roteamento do Gateway API, a persistência de volumes dinâmicos via NFS e o agendamento de tarefas em segundo plano).

Para garantir que o laboratório simule práticas recomendadas de segurança de produção, ambas as aplicações foram configuradas de forma **rootless** (não-root). Isso permitiu alcançar uma pontuação de **Score A (100%) no Popeye**, sem erros (💥) ou avisos (😱).

## 🚀 As Aplicações de Exemplo

### 1. Hello App (`hello-app`)
* **Tecnologia**: Nginx (`nginx:1.29-alpine`).
* **Propósito**: Servir a página inicial do cluster (um dashboard em HTML que exibe atalhos para os serviços ativos como Headlamp, Traefik e Grafana, credenciais de acesso e informações dos nós).
* **Manifestos**:
  * [00-css-configmap.yml](../ansible/100-exemplos/files/hello/00-css-configmap.yml) (Estilos do dashboard)
  * [01-hello-configmap.yml](../ansible/100-exemplos/files/hello/01-hello-configmap.yml) (Estrutura do index.html, contendo o IP e detalhes de atalho do Grafana no IP `172.24.0.103`)
  * [02-hello-deployment.yml](../ansible/100-exemplos/files/hello/02-hello-deployment.yml) (Definição dos Pods com Nginx)
  * [03-hello-service.yml](../ansible/100-exemplos/files/hello/03-hello-service.yml) (Exposição do Pod como Service interno)
  * [04-hello-gateway-httproute.yml](../ansible/100-exemplos/files/hello/04-hello-gateway-httproute.yml) (Configuração de rota no Gateway API do Traefik)
  * [05-hello-pdb.yml](../ansible/100-exemplos/files/hello/05-hello-pdb.yml) (PodDisruptionBudget)
  * [06-hello-hpa.yml](../ansible/100-exemplos/files/hello/06-hello-hpa.yml) (Horizontal Pod Autoscaler baseado em CPU)
  * [07-hello-hpa-teste-stress.yml](../ansible/100-exemplos/files/hello/07-hello-hpa-teste-stress.yml) (CronJob de teste de estresse de carga)
  * [08-hello-networkpolicies.yml](../ansible/100-exemplos/files/hello/08-hello-networkpolicies.yml) (Isolamento de tráfego)
  * [09-hello-vpa.yml](../ansible/100-exemplos/files/hello/09-hello-vpa.yml) (Vertical Pod Autoscaler para otimização de CPU/memória)

### 2. Contador de Acessos (`contador`)

* **Tecnologia**: PHP/Apache (`php:8.5-apache`) + CronJob de apoio (`debian:stable`).
* **Propósito**: Demonstrar a persistência em volumes compartilhados (gravação/leitura no arquivo `contador.txt` e `ultimo.txt` a cada acesso e no arquivo `cron.txt` a cada execução do CronJob).
* **Manifestos**:
  * [02-contador-configmap.yml](../ansible/100-exemplos/files/contador/02-contador-configmap.yml)
  * [03-contador-deployment.yml](../ansible/100-exemplos/files/contador/03-contador-deployment.yml)
  * [06-contador-cronjob.yml](../ansible/100-exemplos/files/contador/06-contador-cronjob.yml)
  * [07-contador-networkpolicies.yml](../ansible/100-exemplos/files/contador/07-contador-networkpolicies.yml)

### 3. Exemplos dedicados de VPA (`vpa`)
* **Propósito**: Demonstrar de forma isolada e sem concorrência com o HPA o funcionamento do Vertical Pod Autoscaler nos modos `Initial` (para CronJobs) e `Auto` (para Deployments contínuos com suporte a alta disponibilidade).
* **Manifestos**:
  * [01-vpa-initial-cronjob.yml](../ansible/100-exemplos/files/vpa/01-vpa-initial-cronjob.yml) (CronJob de estresse periódico e VPA com `updateMode: "Initial"`)
  * [02-vpa-auto-deployment.yml](../ansible/100-exemplos/files/vpa/02-vpa-auto-deployment.yml) (Deployment de 2 réplicas com PDB e VPA com `updateMode: "Auto"`)


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

## 📊 Dimensionamento Automático (HPA & VPA)

Para demonstrar os recursos de escalabilidade automática do Kubernetes, o laboratório inclui configurações tanto para dimensionamento horizontal (HPA) quanto vertical (VPA) na aplicação `hello-app`:

### 1. Horizontal Pod Autoscaler (HPA)
* **Manifesto:** [06-hello-hpa.yml](../ansible/100-exemplos/files/hello/06-hello-hpa.yml)
* **Funcionamento:** Monitora o uso de CPU da aplicação `hello-app` (através dos dados coletados pelo `Metrics Server`) e escala a quantidade de réplicas de 2 (mínimo) a 5 (máximo) caso a média ultrapasse 50% de CPU.
* **Teste de Carga:** O CronJob `hello-hpa-teste-stress` ([07-hello-hpa-teste-stress.yml](../ansible/100-exemplos/files/hello/07-hello-hpa-teste-stress.yml)) roda periodicamente para gerar requisições HTTP artificiais contra o `hello-app`, simulando um pico de acesso e ativando o escalonamento horizontal.

### 2. Vertical Pod Autoscaler (VPA)
* **Manifesto:** [09-hello-vpa.yml](../ansible/100-exemplos/files/hello/09-hello-vpa.yml)
* **Funcionamento:** O VPA monitora os pods para sugerir os limites ideais de CPU e memória de acordo com seu consumo histórico real.
* **updateMode: "Off" (no hello-app):** No Deployment da aplicação, o VPA está configurado no modo `Off` (somente recomendação). Isso é uma boa prática fundamental: VPA e HPA baseado em CPU/memória **não** devem alterar os mesmos recursos do Pod simultaneamente de forma ativa para evitar loops de decisão conflitantes. Com o modo `Off`, o VPA gera relatórios e recomendações estáticas que podem ser analisadas manualmente pelo comando:
  ```bash
  kubectl describe vpa hello-app-vpa -n exemplos
  ```
* **updateMode: "Initial" (no hello-hpa-teste-stress):** Para o CronJob de teste de estresse, a política do VPA é definida como `Initial`. Como não há HPA atuando sobre o CronJob, o VPA calcula e altera os limites de recursos do Pod no momento em que ele é iniciado pela execução periódica, otimizando o contêiner de carga dinamicamente sem reiniciá-lo enquanto executa.

### 3. Testes Dedicados de VPA (Modos Initial e Auto)

Para testar e observar detalhadamente o comportamento do VPA de forma isolada, foram disponibilizados dois cenários sob o diretório `vpa`:

* **VPA Initial com CronJob (`01-vpa-initial-cronjob.yml`):**
  * O CronJob `vpa-stress-cronjob` é executado a cada 10 minutos (especificamente nos minutos terminados em 5, como 5, 15, 25... para evitar concorrência com o teste HPA).
  * O Pod gerado executa um processamento intensivo de CPU por 3 minutos. O VPA associado (`vpa-stress-cronjob-vpa`) com `updateMode: "Initial"` coleta o consumo histórico e, na próxima execução periódica, o novo Pod é automaticamente criado com requisições e limites mais altos, calculados a partir da execução anterior.

* **VPA Auto com Deployment e PDB (`02-vpa-auto-deployment.yml`):**
  * O Deployment `vpa-stress-deployment` roda constantemente com 2 réplicas.
  * Os containers monitoram o relógio do sistema e iniciam o estresse de CPU por 3 minutos quando o minuto atual termina em 5 (ex: 5, 15, 25...).
  * O VPA associado (`vpa-stress-deployment-vpa`) com `updateMode: "Auto"` detecta o pico de uso de CPU que excede a requisição inicial e solicita a evicção dos Pods.
  * O PodDisruptionBudget `vpa-stress-deployment-pdb` garante que pelo menos 1 réplica continue ativa durante o processo. Assim, o VPA Updater despeja as réplicas de forma alternada, permitindo que a nova réplica seja criada e mutada com os novos recursos sem causar indisponibilidade total.


