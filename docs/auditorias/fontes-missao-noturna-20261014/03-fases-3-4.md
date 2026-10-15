# PRIMELINE GO — MISSÃO NOTURNA FASES 3 E 4
## Auditoria end-to-end, resiliência e cobertura transversal

### 1. Contexto e objetivo

As Fases 1 e 2 da auditoria global estão concluídas.

Branch de auditoria:
`codex/auditoria-global-noturna-20261014`

Checkpoint esperado:
`f72686cfdc4f61514a86851aa18de7976242ca56`

Confirmar branch, HEAD e working tree antes de iniciar.

Ler integralmente os relatórios das Fases 1 e 2, especialmente:

- `FASE-2/34-PENDENCIAS-CLASSIFICADAS.csv`
- `FASE-2/PLANO-DE-CORRECOES.md`
- `FASE-2/20-DECISOES-REVISADAS.md`
- `FASE-2/RESUMO-PARA-CHATGPT.md`

Usar os nomes reais existentes quando diferirem.

**Objetivo:** realizar testes profundos de integração e resiliência, demonstrando o comportamento dos processos completos da plataforma, sem implementar correções ou alterar produção.

Trabalhar autonomamente, sem perguntas à utilizadora durante a noite.

### 2. FASE 3 — Testes de processos completos

Não limitar a auditoria à existência de funções, tabelas ou testes isolados.

Para cada processo, construir um cenário sintético completo e verificar cada transição, identificando a origem dos dados, o writer, os leitores e os consumidores.

#### A. Circuito financeiro — prioridade máxima

Percorrer:

Orçamentação → Planeamento → TEE → Auto → Fatura → Recebimento → Mapa Financeiro.

Testar, quando o contrato existente permitir:

- Fatura rascunho versus emitida.
- Autos aprovados e por aprovar.
- Faturação parcial.
- Recebimento de 100 € numa fatura de 1.000 €.
- Recebimento posterior de 900 €.
- Repetição de pedidos.
- Falha na associação entre fatura e auto.
- Valor contratual zero versus valor desconhecido.
- Adiantamentos.
- Divergências entre valores com e sem IVA.
- Distribuição de despesas e subempreitadas entre meses.
- TEE rejeitado após sincronização com Planeamento.

Comparar os resultados entre os diferentes mapas e relatórios.

Os problemas já comprovados na Fase 2 não precisam de novo diagnóstico da causa. Testar sobretudo os seus efeitos nos módulos consumidores e os critérios necessários para futuras correções.

#### B. Administrativo e RH

Percorrer:

Cadastro → Contrato → Alocação → Folha de Ponto → FALTOU → Ausências → Conferência Mensal → Relatórios.

Verificar a integridade do processo e os efeitos de correções posteriores.

Incluir permissões, férias, medicina, documentos e viaturas quando existirem contratos que possam ser exercitados localmente.

Não alterar FP-28/29, nem as regras de horário, almoço ou tolerância ainda por aprovar.

#### C. Compras e fornecedores

Percorrer:

Fornecedor → Consulta → Mapa Comparativo → Proposta → Adjudicação → Documentos → Fatura.

Verificar origem dos preços, unidades, paginação, duplicados, ligações e permissões.

Distinguir preço consultado, proposto, adjudicado e faturado.

Identificar o que poderá ser reutilizado numa futura vista de consulta de preços do Encarregado, sem desenvolver essa interface.

#### D. Equipa Técnica

Percorrer:

Obra → Planeamento → Tarefa → Responsável → Reporte → Validação → Alerta → Atualização dos indicadores.

Identificar operações interrompidas, alterações não propagadas, alertas duplicados e diferenças entre Diretor, Adjunto, Preparador e Encarregado.

### 3. FASE 3 — Testes de resiliência

Executar testes de falha em ambiente sintético descartável:

- Duas sessões concorrentes.
- Operação repetida com o mesmo request_id.
- Revisão desatualizada.
- Cancelamento após preview.
- Falha entre duas escritas.
- Falha de ligação ou resposta HTTP.
- Troca de sessão durante uma leitura.
- Revogação de autorização durante uma operação.
- Referência a documento inexistente.
- Alteração de obra ou empresa.
- Restauro após rollback permitido.
- Escritas parciais e associações órfãs.

Verificar especialmente os efeitos dos P1 N-FIN-01, N-FIN-05 e N-SEC-01, sem repetir as mesmas provas da Fase 2.

Um teste que demonstre a vulnerabilidade continua a ser evidência de falha do produto, mesmo que o teste termine com PASS.

### 4. FASE 3 — Dependências de publicação

Inspecionar a cadeia de migrations e respetivas dependências.

Analisar N-SEC-02 e N-SEC-03:

- Scripts históricos com policies permissivas.
- Sobreposições de definições SQL.
- Ordem de instalação.
- Hashes, owners, ACL e funções substituídas.
- Dependências entre Financeiro, Folha de Ponto, Quadro e Autos.
- Rollbacks históricos potencialmente incompatíveis.

Simular ordens incorretas apenas num PostgreSQL descartável.

Criar um manifesto PROPOSTO de dependências e riscos. Não modificar o manifesto operacional nem executar migrações reais.

### 5. FASE 4 — Cobertura transversal, se a Fase 3 terminar cedo

Prosseguir autonomamente para uma auditoria de cobertura funcional das 38 áreas identificadas na Fase 1.

Não repetir genericamente os inventários anteriores.

Para cada área, procurar especificamente:

1. Ações visíveis na interface sem writer funcional.
2. Writers implementados sem interface acessível.
3. Leitores sem controlo de erro ou paginação.
4. Permissões diferentes entre frontend e backend.
5. Estados que não chegam aos relatórios.
6. Funcionalidades sem regressões representativas.
7. Fluxos que permitem dados parciais.
8. Código legado potencialmente ativo.
9. Dependências de outras branches ainda não integradas.
10. Documentação que descreve comportamento obsoleto.

Criar uma matriz que relacione cada conclusão com o código e os testes correspondentes.

Aprofundar primeiro os módulos com lacunas de cobertura demonstráveis, não simplesmente os módulos com maior quantidade de ficheiros.

### 6. Questões e decisões

Não interromper a execução para pedir decisões.

Registar questões funcionais e dependências externas com:

- Problema concreto.
- Evidência.
- Consequência.
- Alternativas.
- Recomendação técnica.
- Módulos afetados.
- Decisão que precisamos de tomar.

Não reabrir HR-27, HR-30, HR-31 ou decisões de Gestão de Horas já aprovadas.

HR-38 tem apenas aprovação de princípio para custo-padrão operacional por função/nível.

HR-41 permite ajustes individuais RH confidenciais pelo Administrativo autorizado.

Aprovação da tabela-padrão e regras de vigência continuam por fechar. Não implementar alterações relacionadas durante esta missão.

### 7. Autonomia e segurança

Pode executar análises estáticas, scripts de inspeção e testes com dados sintéticos em ambiente isolado.

Pode criar documentação, matrizes e testes de diagnóstico.

Não modificar o código funcional da aplicação.

Não executar SQL real, push, merge, deploy, alterações no Cloudflare ou na BD hospedada.

Não aceder a dados pessoais reais.

Não instalar ferramentas que exijam aprovação externa nem ficar bloqueado indefinidamente à espera de permissões.

Se uma operação exigir autorização, registar a limitação e avançar para outra tarefa independente.

Não executar reset destrutivo, limpeza do repositório ou remoção de histórico.

### 8. Checkpoints e organização

Continuar preferencialmente na worktree isolada da auditoria existente, preservando a branch principal e os relatórios anteriores.

Criar:

`docs/auditorias/auditoria-global-noturna-20261014/FASE-3/`

e, se a Fase 4 for iniciada:

`docs/auditorias/auditoria-global-noturna-20261014/FASE-4/`

Guardar relatórios progressivamente e criar commits locais de documentação/testes quando estiverem consistentes.

Não esperar pela conclusão integral para guardar resultados.

Não trabalhar artificialmente até às 06h00. Se todos os trabalhos úteis forem concluídos, terminar normalmente e preservar o checkpoint.

A utilizadora poderá interromper a execução pela manhã; manter sempre documentação recuperável.

### 9. Entrega final

Produzir:

**FASE-3**

- `MATRIZ-END-TO-END.csv`
- `FINANCEIRO-END-TO-END.md`
- `ADMINISTRATIVO-RH-END-TO-END.md`
- `COMPRAS-EQUIPA-TECNICA.md`
- `TESTES-RESILIENCIA.md`
- `MIGRATIONS-E-PUBLICACAO.md`
- `NOVAS-DESCOBERTAS.csv`
- `QUESTOES-PARA-DECISAO.md`
- `RESUMO-PARA-CHATGPT.md`
- `RETOMA.md`

**FASE-4, caso seja iniciada**

- `COBERTURA-38-AREAS.csv`
- `INTERFACES-WRITERS-LEITORES.md`
- `COBERTURA-POR-PERFIL.md`
- `TESTES-EM-FALTA.csv`
- `DIVERGENCIAS-DOCUMENTACAO.md`
- `RESUMO-FINAL.md`
- `RETOMA.md`

Em todos os documentos, distinguir claramente:

- Falha comprovada.
- Vulnerabilidade reproduzida.
- Comportamento correto.
- Funcionalidade ainda não implementada.
- Limitação do ambiente de teste.
- Hipótese por verificar.

Indicar caminho, função, linha e prova para as descobertas relevantes.

Não criar códigos oficiais novos do Backlog Mestre. Propor IDs temporários e indicar possíveis correspondências com os itens existentes.

### 10. Encerramento

Apresentar um relatório curto com:

- Fases concluídas.
- Novas descobertas relevantes.
- Testes executados e resultados.
- Itens ainda não investigados.
- Perguntas para decisão.
- Branch, SHA e working tree.
- Riscos de publicação.

**Produto e produção devem permanecer inalterados.**

Não iniciar publicações, correções funcionais ou migrações.

Objetivo: entregar uma auditoria técnica aprofundada e verificável, pronta para análise e integração posterior no Backlog Mestre global.