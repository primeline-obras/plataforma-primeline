# Segunda varredura crítica — Quadro controlado

## Decisão

**Varredura interrompida por P1 confirmado. NO-GO para fechar/publicar o Pacote 1 e para executar a Fase B.** Nenhuma correção foi feita. A execução completa dos restantes ataques fica pendente, conforme a ordem de parar ao encontrar P0/P1.

- Candidato: `80d41cc4dbeb4eaa88d0359f5207f6f6a4f85beb`.
- Branch de auditoria: `audit/quadro-controlado-pacote1-critica2-20261001`, criada exatamente desse SHA.
- Base indicada: `9e0e6c40b439160201289823db8cfee0b9adad02`.
- Teste independente: `tests/workforce-critica2.test.mjs`, derivado da fixture do candidato com ataques adicionais à barreira de rollout. Não é uma prova independente de todos os componentes periféricos: a fixture contém stubs explicitamente identificados.

## P1-01 — Barreira da Fase B aceita identificação arbitrária e reutilizada

Locais: `supabase/quadro_controlado_fase_b.sql:6`, `supabase/quadro_controlado_fase_b_forward_fix.sql:7` e final de `supabase/quadro_controlado_fase_b_precheck.sql`.

A única condição relativa ao frontend é:

```sql
IF nullif(current_setting('primeline.quadro.frontend_validado',true),'') IS NULL THEN
  RAISE EXCEPTION 'PRECONDITION_FAILED: falta identificação do frontend publicado e validado.';
END IF;
```

O precheck apenas apresenta o valor. Não valida SHA, candidato publicado, autorização de quem registou a validação, momento de validação nem consumo da autorização.

### Prova executada — PostgreSQL 17.6 local

1. Em `SET LOCAL ROLE authenticated`, executar:

```sql
SELECT set_config('primeline.quadro.frontend_validado','not-a-sha',true);
```

Resultado: `not-a-sha`, sem erro.

2. Na sessão do operador local, definir o mesmo texto inválido, realizar backup B e executar integralmente a Fase B.
3. A instalação e o postcheck B passam, apesar de não existir SHA válido.
4. Efetuar rollback B e reaplicar o forward-fix B com o sinalizador inválido ainda definido.
5. O forward-fix e o postcheck passam novamente. A autorização não é consumida nem exige nova validação.

**Limite importante:** isto não prova que authenticated consiga executar a migration ou ultrapassar DML/RLS. O sinalizador não concede privilégios e o teste de falsificação do sinalizador de escrita continua a recusar DML. A falha é na precondição operacional exigida para fechar os clientes antigos, não um bypass demonstrado de escrita.

Impacto: um operador pode fechar a API antiga e o DML sem confirmação verificável do frontend publicado; o mesmo sinalizador pode autorizar uma aplicação posterior. O backup existente também não associa essa identificação a um rollout específico.

Correção a discutir, sem implementar nesta auditoria: substituir o texto livre como prova por uma autorização explícita, protegida, vinculada ao SHA esperado e à operação/backup atual; recusar identificação inválida ou reutilizada. Não confiar num custom GUC como autenticação.

## Testes e resultados

Comando: `node --test tests/workforce-critica2.test.mjs`, com QUADRO_PG_BIN e QUADRO_TEST_DEPS apontados para PostgreSQL 17.6 e pg locais.

**59 testes passaram; 0 falharam; 0 skips.** Os testes de ataque passam porque reproduzem o defeito; não significam aprovação da Fase B.

Cobertura efetivamente executada nesta sessão:

- DML e RPC legados antes/A; API v1 em A/B; cliente antigo/B recusado.
- Snapshot sintético de 227 alocações e 98 movimentos preservado.
- Data explícita, ausência já existente, conflito, split/merge, remoção e renomeação.
- Empresa, Administrativo/Gestão, Gerência sem escrita global, Encarregado com origem/destino autorizados, Diretor/Adjunto leitura limitada, Preparador e utilizador inativo.
- Cadastro com/sem alocação, falhas atómicas, importação existente e rollback por erro de linha.
- Revisão vazia para manhã/tarde/dia inteiro, reload/replay, ABA.
- Duas ligações: mesma revisão → STALE; mesmo request → idempotência; payload diferente → conflito; Encarregado após estado vazio.
- Notificação básica: preview zero, commit, replay, remoção e rollback.
- DML direto e sinalizador de escrita falsificado recusados.
- Postcheck recusa grant privado, helper exposto e policy permissiva.
- Rollback/forward-fix A/B preservam dados nos cenários da suíte.

O teste reutiliza dados sintéticos; **não reproduz os 27 pares reais de sobreposição nem certifica os dois casos reais de coexistência com ausência**. Não houve consulta ou escrita de produção nesta sessão.

## Revalidação dos achados anteriores

| Achado anterior | Resultado nesta segunda varredura |
|---|---|
| P0 rollout incompatível | Contratos SQL antigo/antigo, antigo/A, novo/A, novo/B e falha segura antigo/B passam. Não certifica browsers antigos reais; novo P1 impede aprovar a transição B. |
| P0 Ponto sem cobertura | Teste confirma comportamento temporal legado e ausência de redefinição das duas RPCs de Ponto. Sem alocações artificiais na instalação sintética. **Dívida transitória intencional — remover no Pacote 2**. |
| P1 Gerência | Testes confirmam consulta/RH preservados e escrita global do novo Quadro recusada. |
| P1 revisão vazia | Casos dos três períodos, replay/reload e concorrência de Encarregado passam. |
| P1 notificações | Casos básicos passam com notificador instalado na fixture. Índice único real e matriz completa split/merge/destinatários ainda não certificados. |
| P1 backup/postcheck | Grants privados, helper, policy e preservação de contratos testados. Não encerrado: barreira B falha; restante completude/concorrência da fotografia pendente. |
| P2 rollback após uso | Rollback e forward-fix passam nos cenários da suíte; resposta perdida atravessando rollback não testada. |
| P2 obra encerrada | Não revalidado; não declarar resolvido. |
| P2 mobile/UX | Não revalidado nesta sessão. |
| P2 cadastro novo sem idempotência | Não revalidado; não declarar resolvido. |
| P2 consumidores/ausência posterior | Ausência preexistente recusada; criação concorrente de ausência durante movimento não testada. |
| P3 manutenção | Sem nova certificação. |

## Estado por área e limites restantes

- **Rollout A/B:** separação compatível demonstrada em SQL; gate B não confiável. Nenhuma publicação autorizada pelo resultado.
- **Rollback/forward-fix:** preservação básica confirmada; sinalizador inválido reutilizado no forward-fix B; perda de resposta antes/depois de rollback não certificada.
- **Locks:** concorrência de mesma pessoa/revisão/request testada em duas ligações. Não medidos tempos sob carga, starvation, deadlocks entre RH/legado/novo em pessoas diferentes ou corrida com ausência; não concluir segurança completa.
- **Permissões:** matriz principal passa localmente, sem bypass de DML demonstrado. Validação da autoridade do sinalizador de rollout falha.
- **RH:** atomicidade e ausência de continuidade implícita passam nos cenários existentes. Não certifica todas as falhas após contrato em todas as fases/rollbacks.
- **Ponto:** funções/comportamento legado preservados pelos testes; dívida temporal permanece intencional.
- **Notificações:** básicos passam; índice único real, todos os destinatários e split/merge pendentes.
- **Regressões:** executada a suíte SQL sintética do Quadro; browsers e regressões integrais de outros módulos não repetidos após o P1. Resultados da sessão anterior não contados como nova prova.
- **Fotografia real 227/98/27/2:** não consultada nesta auditoria; fixture não equivale à fotografia real completa.

## P0/P1/P2/P3 e autorização

- P0: nenhum novo confirmado no trecho auditado; auditoria interrompida, não significa ausência.
- P1: barreira da Fase B e forward-fix confirmada.
- P2: pendências anteriores e provas incompletas acima; não reclassificar testes obrigatórios não executados como aprovação.
- P3: sem achado novo confirmado.

| Etapa | Decisão |
|---|---|
| Fase A | GO não emitido: verificações locais favoráveis, mas segunda varredura não concluída. |
| Frontend | NO-GO para publicação como Pacote 1 aprovado; regressão completa e gate de transição pendentes. |
| Fase B | **NO-GO**, P1 reproduzido. |

Próxima sequência: rever o P1, corrigir numa tarefa separada no candidato e repetir a auditoria dos ataques obrigatórios ainda pendentes. Não há sequência de instalação/publicação aprovada neste relatório.

## Integridade

Somente este relatório e o teste de auditoria foram criados no worktree separado. Candidato não corrigido. Nenhuma escrita em produção, nenhuma migration real, nenhum deploy, nenhum merge e nenhum push.
