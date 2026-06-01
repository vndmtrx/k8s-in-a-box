# Guia de Contribuição

Obrigado por seu interesse em contribuir com o projeto [K8s in a Box](https://github.com/vndmtrx/k8s-in-a-box)! Este é um projeto educacional que visa ensinar sobre Kubernetes através de uma instalação manual automatizada com Ansible, similar ao "Kubernetes The Hard Way", mas com um toque brasileiro.

## Princípios do Projeto

1. **Foco Educacional**: Todo o código e documentação devem servir ao propósito de ensinar.
2. **Clareza sobre Otimização**: Preferimos código claro e bem documentado a código otimizado mas complexo.
3. **Documentação é Crucial**: A documentação do processo é tão importante quanto o código.
4. **Ambiente Reproduzível**: O ambiente deve ser facilmente destruído e recriado.

## Como Contribuir

### Preparação do Ambiente
1. Requisitos básicos:
   - Git
   - Vagrant
   - LibVirt
   - Ansible
   - Python 3.x

2. Clone o repositório:
   ```bash
   git clone https://github.com/vndmtrx/k8s-in-a-box.git
   cd k8s-in-a-box
   ```

### Tipos de Contribuição

#### Documentação (Prioridade Alta)
- Melhorias na clareza das explicações
- Correções de português
- Documentação de processos
- Adição de exemplos práticos
- Esclarecimentos sobre conceitos
- Tradução de termos técnicos (quando apropriado)

#### Código (Avaliado Caso a Caso)
- Correções de bugs
- Melhorias de segurança
- Novos recursos educacionais
- Exemplos adicionais de uso
- **Importante**: Mudanças que obscurecem o entendimento não serão aceitas

### Processo de Contribuição

1. **Teste suas alterações**:
   ```bash
   make clean         # Destrua o ambiente atual
   make kiabo         # Recrie do zero
   vagrant ssh kubox  # Acesse as ferramentas do cluster
   ```

2. **Envie um Pull Request**:
   - Use a branch main como base
   - Forneça uma descrição detalhada das alterações
   - Explique o valor educacional da mudança
   - Documente qualquer novo processo
   - Se for mudança de código, explique por que ela ajuda no entendimento

### Diretrizes

#### Documentação
- Escreva em português claro
- Explique os "porquês", não apenas os "comos"
- Use exemplos práticos
- Mantenha um tom educacional
- Documente processos passo a passo

#### Código
- Comente em português
- Priorize clareza sobre concisão
- Explique decisões de implementação
- Mantenha a consistência com o estilo existente
- Documente premissas e requisitos

## Estrutura do Projeto

- `ansible/`: Playbooks e roles do Ansible
- `docs/`: Documentação do projeto
- Arquivos na raiz: Configuração do ambiente

## Problemas?

- Use o ambiente padrão do Vagrant
- Certifique-se de destruir e recriar o ambiente ao testar
- Documente erros encontrados
- Abra uma issue descrevendo o problema

## Dúvidas e Contato

- Abra uma issue no GitHub para:
  - Dúvidas sobre o projeto
  - Sugestões de melhorias
  - Discussões sobre implementações

## Licença

Ao contribuir, você concorda que suas contribuições serão licenciadas sob a mesma licença MIT do projeto.

---

Lembre-se: Este é um projeto educacional. Cada contribuição deve tornar o projeto (e o Kubernetes) mais compreensível para os outros! 📚
