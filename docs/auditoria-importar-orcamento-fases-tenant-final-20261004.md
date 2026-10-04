# Reauditoria final de fn_importar_orcamento_fases

Data: 04/10/2026. Auditoria defensiva local, limitada à classe e às suites já preparadas.

## Identificação e conclusão

- SHA auditado: `368f07a19dd274760b1743bcd33d6c3a204c15fc`.
- Candidato: `fix/importar-orcamento-fases-tenant-20261004`.
- Branch desta auditoria: `audit/importar-orcamento-fases-tenant-final-20261004`, criada exatamente no SHA auditado, com working tree limpo.
- Auditoria anterior preservada: `audit/writers-economicos-tenant-final-20261004`, SHA `19d9bc41e2440143c1ad6d4fe978c9d942d76b5d`.
- Apenas este relatório foi acrescentado. Nenhum ficheiro do produto ou teste foi corrigido durante a reauditoria.
- O SHA do commit do relatório consta da entrega; não é incluído aqui para evitar autorreferência.

**GO técnico para rollout real controlado. HOTFIX DE AUTORIZAÇÃO APTO PARA ROLLOUT REAL CONTROLADO.**

O P1 original está fechado, as suites terminaram com **387 PASS / 0 FAIL / 4 SKIP**, a busca residual focada devolveu **ZERO** e os cinco scripts passaram no ensaio local. Nenhum P0/P1 restante foi confirmado nesta classe. O GO exige executar o precheck real imediatamente antes do rollout: catálogo sem drift e zero incoerências históricas. Não constitui autorização para aplicar SQL.

## P1 original e cenários A–E

Foi reexecutado o teste original que falhou na auditoria anterior, mantendo a expectativa: fase da obra A, target de orçamento na obra B, ator autorizado em A. A chamada agora devolve **42501**. As verificações complementares comparam todas as tabelas sintéticas, incluindo os campos económicos e o log de auditoria, antes/depois das recusas.

| Verificação | Resultado independente |
|---|---|
| P1 original: fase A / target B de outra empresa | PASS: 42501 |
| A: target inconsistente noutra obra da mesma empresa | PASS: 42501; linha e demais dados intactos |
| B: target existente correto | PASS: UPDATE; ID preservado; custo, venda, margem e materiais corretos; auditoria presente |
| C: target inexistente | PASS: INSERT legítimo e auditado |
| D: payload com primeira fase válida e segunda inconsistente | PASS: recusa integral; nenhuma escrita ou auditoria parcial |
| E: target de outra empresa | PASS: 42501; todos os campos económicos preservados |

Evidências: `tests/writers-economicos-final-audit-cases.mjs` e `tests/orcamento-fases-target-cases.mjs`, executados pelo harness `tests/financeiro-cross-tenant.test.mjs` em PostgreSQL local. Não foram criados novos cenários de exploração.

## Concorrência

PASS por revisão e ensaio preparado com duas ligações PostgreSQL.

1. O guard central autoriza o ator e a obra. A fase é lida com `FOR SHARE`, preservando a sua obra durante a operação.
2. Um target existente é lido com `FOR UPDATE`; a comparação exige a mesma obra, além da autorização da empresa. O lock impede a reatribuição concorrente desse target entre validação e escrita.
3. Todas as linhas são pré-validadas antes do primeiro INSERT/UPDATE.
4. Um target ausente pode surgir concorrencialmente. O `ON CONFLICT` exige novamente `orcamento_fases.obra_id = EXCLUDED.obra_id`. `ROW_COUNT <> 1` provoca 42501 e rollback da chamada inteira, evitando uma recusa silenciosa.

O ensaio observou a importação em espera de lock enquanto outra ligação mantinha um novo target estrangeiro não confirmado. Após o COMMIT da outra ligação, a importação recusou com 42501; o target manteve a obra e o custo originais. Este ensaio comprova a proteção do caminho de conflito tardio; o caso de target já existente é também sustentado pelos locks de linha revistos no corpo SQL.

## Precheck histórico

PASS. `encarregado_escopo_precheck.sql` usa `BEGIN READ ONLY` e termina com `ROLLBACK`. O gate compara `orcamento_fases.obra_id` com `fases.obra_id`, via `fase_id`, incluindo fase inexistente.

- Zero incoerências: o precheck completo passou no catálogo reconstruído localmente.
- Incoerência ou fase inexistente: erro **23514 / ORCAMENTO_FASES_OBRA_DIVERGENTE**; nenhuma linha alterada.
- O DETAIL contém apenas `orcamento_fase_id`, `fase_id`, `obra_orcamento_id` e `obra_fase_id`.
- Não apresenta nomes, valores económicos ou correção automática.
- O mesmo bloco está presente em backup, migration e postcheck, verificado pela suite.

Esta auditoria não recapturou o Supabase real. Não afirma que hoje existam zero incoerências em produção.

## Regressão final e busca residual

As suites existentes voltaram a validar os 28 writers económicos, as seis RPCs financeiras, os quatro P0 originais, helpers privados e os casos de alertas/utilizador inativo. Os casos de baseline reproduzem as falhas apenas na base local reconstruída; as verificações após instalação confirmam as recusas previstas.

O ramo de despesas gerais de `fn_importar_mapa_financeiro_xlsx` permanece explicitamente bloqueado com **0A000 / DESPESAS_GERAIS_BLOQUEADAS**, antes de qualquer escrita ou log, em ambas as ordens de payload. A importação legítima por obra permanece funcional. Nenhum tenant histórico foi inventado.

Regressões de sessão, Quadro, RH, Medicina, Financeiro, Planeamento, Subempreitadas/comparativos, RNC, documentos e Viaturas: PASS nas suites locais preparadas.

Busca residual: executado o scanner existente `tests/writers-economicos-final-scan.mjs`, com **41 entradas / residual vazio / ZERO**. Não foi ampliada a busca. O resultado textual foi confrontado com os testes semânticos do P1; sozinho não prova isolamento.

## Scripts consolidados

| Script em supabase | Revisão e execução local |
|---|---|
| `encarregado_escopo_precheck.sql` | PASS: leitura, fingerprint do catálogo/ACL e gate histórico; drift recusa |
| `encarregado_escopo_backup.sql` | PASS: gate antes do snapshot privado; definições e ACLs originais recuperáveis |
| `encarregado_escopo_migration.sql` | PASS: transação, baseline/backup verificados e definição corrigida de `fn_importar_orcamento_fases(uuid,jsonb,text)` instalada |
| `encarregado_escopo_postcheck.sql` | PASS: leitura, gate, comparação do catálogo instalado, contratos/ACLs e hash do corpo corrigido `429978a320a0c174b517757382a5b63f`; drift posterior recusa |
| `encarregado_escopo_rollback.sql` | PASS: restaura exatamente catálogo e acesso anteriores; recupera definição/ACL original do importador pelo snapshot |

A comparação da migration com a base anterior confirma alteração do corpo apenas do importador de fases, além do gate. O rollback permanece idêntico ao da base. As tabelas operacionais sintéticas ficaram integralmente intactas ao final do ensaio SQL/REST.

O fingerprint cobre funções, owners, ACLs de tabelas/colunas, RLS, policies e views. Não é uma fotografia integral de todos os índices, defaults, constraints e triggers. A fixture local acrescenta as estruturas necessárias aos ensaios; este limite não deve ser confundido com um levantamento novo da produção.

## Execuções e resultados

| Grupo | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| PostgreSQL/PostgREST + estáticos de writers, P1, A–E, concorrência, gate e scripts | 127 | 0 | 0 |
| Quadro/RH e Medicina nativos | 197 | 0 | 0 |
| Clientes e regressões essenciais | 63 | 0 | 4 |
| **Total, sem duplicar execuções** | **387** | **0** | **4** |

Comandos principais:

```text
node --test tests/financeiro-cross-tenant.test.mjs tests/writers-economicos-static.test.mjs tests/writers-economicos-final-static.test.mjs
node --test tests/workforce-controlled.test.mjs tests/medicina-trabalho.test.mjs
```

Grupo de clientes: access-control, rh-cadastro, collaborator-lifecycle, medicine-client, absences-workflow, workforce-vacations, subcontract-contract-control, finance-operational-access, duplicate-invoice-warning, planning-batch, planning-safeupdate, rnc-module, company-documents, documents-center, vehicles-module, vehicle-assignment-client, workforce-alerts, alerts-expiry-resolution, session-boundary, session-isolation, foreman-scope e workforce-allocation-client (`tests/*.test.mjs`).

Os quatro SKIPs preparados foram mantidos. Não foram contabilizados como PASS nem substituídos por novos testes.

Browser separado, com dados sintéticos e tráfego externo interceptado:

- `session-boundary-browser.mjs`: PASS, sete cenários de sessão.
- `encarregado-rnc-browser.mjs`: PASS, seis perfis.
- `workforce-controlled-browser.mjs`: PASS, RPC ausente sem DML antigo, falha preserva UI, ações/âmbito, três viewports e console.
- `medicine-browser.mjs`: PASS, consulta/histórico, NULL, estados, replay, stale revision, inativo, quatro perfis, três viewports, sem DML direto e console.
- `vehicle-assignment-browser.mjs`: PASS, contrato controlado, idempotência/permissões e desktop/mobile.

`git diff --check`: PASS. Nenhuma etapa essencial ficou bloqueada pelo ambiente nesta reauditoria.

## Limites e próximo gate

P0/P1 restantes confirmados nesta classe: **zero**. Nenhuma regressão nova encontrada nas verificações executadas. A conclusão é limitada à classe solicitada e às evidências locais; os quatro SKIPs continuam omissões explícitas.

Antes do rollout real: autorização expressa, precheck real completo e interrupção se houver drift ou incoerência obra/fase. A reconciliação histórica, se necessária, exige tarefa própria.

Nenhum SQL foi aplicado em produção, nenhum dado real foi alterado, main permaneceu em `d6db2c3c9e48170a3d4c6ec937b5f7ad76e411fb`. Não houve publicação, marcador B ou Fase B.
