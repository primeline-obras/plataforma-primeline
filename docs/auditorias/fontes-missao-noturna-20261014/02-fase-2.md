# PRIMELINE GO — AUDITORIA NOTURNA, FASE 2

## Contexto

A primeira auditoria global foi concluída antecipadamente às 20h45.

Branch: `codex/auditoria-global-noturna-20261014`

Checkpoint: `439b1e3b900a8d5b919062cf8efd1f05868e494a`

Resultado anterior: 38 áreas, 34 pendências, 20 decisões e 236 testes aprovados.

**Objetivo desta fase: aprofundar os problemas identificados e preparar soluções, sem alterar o produto.**

Trabalhar autonomamente até concluir os trabalhos seguros disponíveis. Não é necessário permanecer ativo até às 06h00 se tudo estiver concluído.

## 1. Rever os resultados da primeira auditoria

Ler integralmente os dez documentos gerados em:

`docs/auditorias/auditoria-global-noturna-20261014/`

Confirmar as evidências associadas às 34 pendências e às 20 questões.

Não repetir análises já concluídas, salvo quando necessário para validar uma descoberta.

## 2. Análise adversarial dos três P1

### P1 — HTML executável

Identificar todos os renderizadores afetados, a origem dos dados, os caminhos de execução e os perfis potencialmente expostos.

Investigar outros componentes que utilizem HTML dinâmico, incluindo documentos, comentários, descrições, históricos, alertas e mensagens.

Reproduzir os problemas exclusivamente com dados sintéticos.

Preparar proposta de correção que preserve a apresentação legítima dos conteúdos.

### P1 — Criação não atómica de faturas

Mapear o percurso completo desde o formulário até à persistência.

Identificar todos os registos e documentos associados à fatura, incluindo fornecedor, obra, subempreitada, anexos e histórico.

Simular falhas em diferentes etapas e identificar estados inconsistentes.

Propor operação transacional, tratamento de concorrência, idempotência e recuperação de erros.

### P1 — Recebimentos parciais

Examinar a distinção entre:

- Valor faturado.
- Valor recebido.
- Saldo por receber.
- Recebimento parcial.
- Recebimento integral.
- Estado de pagamento e faturação.

Investigar outros consumidores que possam interpretar incorretamente o estado da fatura, incluindo mapas financeiros, relatórios, alertas e previsões.

Preparar exemplos sintéticos e testes de regressão.

**Não modificar os fluxos financeiros reais.**

## 3. Procurar problemas da mesma família

Fazer uma análise transversal para identificar falhas semelhantes às três descobertas anteriores.

Dar prioridade a:

- Outros escritores não atómicos.
- Estados financeiros calculados incorretamente.
- Integrações entre documentos e entidades.
- Falhas de autorização em operações económicas.
- Renderização de dados externos.
- Divergências entre frontend, RPC e base de dados.
- Possíveis duplicações e inconsistências de histórico.

Distinguir claramente novos problemas comprovados de hipóteses.

## 4. Aprofundar as 34 pendências

Para cada pendência da primeira auditoria, identificar:

- Se exige correção técnica ou decisão funcional.
- Componentes envolvidos.
- Gravidade.
- Dependências.
- Critérios objetivos de aceitação.
- Testes necessários.
- Possibilidade de correção independente.
- Risco de regressão.

Criar uma ordem de implementação recomendada, considerando impacto, dependências e risco.

Não inventar decisões para preencher lacunas.

## 5. Questões para aprovação

Reorganizar as 20 questões encontradas na primeira auditoria.

Separar:

1. Questões efetivamente bloqueantes.
2. Questões que podem aguardar.
3. Questões resolvidas por regras já documentadas.
4. Questões sem evidência suficiente.

Consolidar perguntas duplicadas e apresentar alternativas acompanhadas de recomendação técnica.

Não interromper a utilizadora durante a execução.

## 6. Testes

Pode criar testes adicionais de diagnóstico e regressão em ambiente local descartável.

Não alterar o código funcional, os contratos de produção ou as permissões.

Não enfraquecer testes existentes.

Um teste que reproduza uma vulnerabilidade deve ser identificado como evidência de falha de segurança, mesmo que tecnicamente passe.

## 7. Segurança e autonomia

Não executar:

- SQL real ou operações no Supabase hospedado.
- Push ou merge.
- Deploy ou alterações no Cloudflare.
- Alterações funcionais ao produto.
- Modificações às regras de negócio.
- Operações destrutivas.
- Acesso a dados pessoais reais.

Não pedir decisões durante a noite. Se encontrar um bloqueador, documentá-lo e avançar com outra tarefa independente.

Guardar o trabalho progressivamente.

## 8. Entrega

Criar uma subpasta `FASE-2` dentro da pasta de auditoria existente.

Produzir:

1. `P1-ANALISE-TECNICA.md` — causas, provas e propostas de correção.
2. `P1-TESTES.md` — cenários reproduzidos e resultados.
3. `AUDITORIA-TRANSVERSAL.md` — outros problemas da mesma família.
4. `34-PENDENCIAS-CLASSIFICADAS.csv` — triagem técnica completa.
5. `20-DECISOES-REVISADAS.md` — questões consolidadas.
6. `PLANO-DE-CORRECOES.md` — prioridades, dependências e critérios de aceitação.
7. `RESUMO-PARA-CHATGPT.md` — principais conclusões e decisões necessárias.
8. `RETOMA.md` — branch, SHA, testes, trabalhos concluídos e pendentes.

Criar commits LOCAIS apenas de documentação, testes e evidências seguras.

Não enviar para o GitHub.

**Objetivo: deixar os três P1 preparados para uma futura correção controlada e transformar as 34 pendências num plano verificável de desenvolvimento.**

Se terminar antes das 06h00, encerrar normalmente, preservando os resultados. Não criar trabalhos artificiais para ocupar tempo.