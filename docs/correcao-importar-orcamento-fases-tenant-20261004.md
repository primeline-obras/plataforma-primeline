# Correção cirúrgica do target de orçamento de fases

Data: 04/10/2026. Branch: `fix/importar-orcamento-fases-tenant-20261004`.

Base exata: candidato `c79b6e406005c92077d358c1d4502d3bb34c125f`. Auditoria preservada e enviada para origin: `audit/writers-economicos-tenant-final-20261004`, SHA `19d9bc41e2440143c1ad6d4fe978c9d942d76b5d`. O candidato anterior permanece intacto nessa branch.

## Causa e correção

fn_importar_orcamento_fases autorizava a obra e a fase recebidas, mas o ON CONFLICT(fase_id) podia atualizar uma linha existente de orcamento_fases cuja obra_id pertencesse a outra obra/empresa. A auditoria comprovou isso com dados sintéticos.

Somente esta função foi alterada. Contrato de parâmetros/defaults/retorno, permissões funcionais, cálculos, campos importados e contagem de linhas permanecem preservados.

1. Autorizar ator e obra pelo guard central existente.
2. Pré-validar todas as linhas: fase existente na obra autorizada, bloqueada com FOR SHARE.
3. Para cada fase, procurar o orçamento existente e bloquear com FOR UPDATE. Se a obra do alvo divergir, devolver 42501 com mensagem genérica, sem revelar dados da outra empresa.
4. Somente após terminar toda a pré-validação, executar as escritas.
5. No upsert, exigir novamente igualdade entre obra_id do alvo e EXCLUDED.obra_id. Verificar ROW_COUNT e levantar o mesmo erro 42501 se a escrita não ocorrer. A condição WHERE é uma proteção adicional de concorrência; não constitui uma recusa silenciosa nem substitui a pré-validação.

Nenhuma linha histórica é movida, reatribuída ou corrigida. Uma falha cancela a chamada inteira, incluindo alterações e auditoria. Não foram introduzidos backfills nem inferências de tenant.

## Concorrência

O lock da fase preserva a sua obra; o lock de um alvo existente impede a sua alteração concorrente durante a importação. Um alvo ausente pode surgir após a pré-validação. A igualdade na cláusula de conflito e a verificação de ROW_COUNT impedem que esse novo alvo estrangeiro seja atualizado ou silenciosamente ignorado.

O ensaio com duas ligações PostgreSQL confirmou este último caso: a segunda ligação inseriu um alvo estrangeiro ainda não confirmado; a importação chegou à espera de lock no conflito; após confirmação da segunda ligação, a importação devolveu 42501 e o alvo permaneceu integralmente na obra original, com custo original. Nenhuma alteração de produção foi usada.

## Scripts

| Script | Alteração/verificação |
|---|---|
| precheck | Gate READ ONLY de incoerência obra/fase, com erro 23514 e detalhe apenas de UUIDs |
| backup | Mesmo gate antes da criação do snapshot privado; definições/ACLs originais continuam cobertas |
| migration | Mesmo gate antes de instalar alterações; corpo corrigido apenas de fn_importar_orcamento_fases |
| postcheck | Mesmo gate e novo hash do corpo: 429978a320a0c174b517757382a5b63f |
| rollback | Mantido sem alteração: já restaura a definição/ACL original desta função pelo snapshot; reexecutado e aprovado |

O gate compara orcamento_fases.obra_id com fases.obra_id por LEFT JOIN e recusa também referência sem fase existente. A mensagem é ORCAMENTO_FASES_OBRA_DIVERGENTE; DETAIL contém orcamento_fase_id, fase_id, obra_orcamento_id e obra_fase_id. Não inclui nomes, valores económicos nem PII. Um precheck futuro real que encontre divergência deve parar para reconciliação manual; esta tarefa não consultou nem corrigiu dados reais.

O novo inventário mantém a definição original recuperável e atualiza somente o hash do corpo corrigido. O ensaio completo confirmou precheck, backup, instalação, postcheck, preservação de dados sintéticos e rollback exato do catálogo/privilégios anteriores.

## Testes

O teste original falhado da auditoria foi trazido sem alterar a sua expectativa e agora passa. O teste funcional adicional de confirmação/replay do custo de Planeamento também continua aprovado.

| Cenário | Resultado |
|---|---|
| A: fase da obra autorizada com target noutra obra da mesma empresa | 42501; linha original intacta |
| B: target correto já existente | UPDATE normal; ID preservado; custo/venda/margem/componentes atualizados |
| C: target ausente | INSERT normal |
| D: primeira fase válida e segunda com target estrangeiro | Recusa integral; sem primeira linha, alteração parcial ou log parcial |
| E: target pertencente a outra empresa | 42501; todos os campos económicos e demais tabelas intactos |
| Gate de incoerência/missing phase | Recusa com UUIDs; nenhuma escrita |
| Alvo ausente surgindo por concorrência | Recusa explícita 42501; nenhum upsert estrangeiro |

Nos cenários A–E foi instalado localmente o trigger de auditoria real de orcamento_fases. Nas recusas, comparou-se o conteúdo de todas as tabelas sintéticas antes/depois, incluindo log_auditoria. Os casos legítimos verificaram auditoria e valores persistidos. O ensaio concorrente é exclusivamente local e remove os seus dados/índice ao terminar.

| Grupo | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| PostgreSQL/PostgREST, 28 writers, P1 original, cenários A–E, gate/concorrência, seis RPCs financeiras, P0 anteriores e scripts | 127 | 0 | 0 |
| Quadro/RH e Medicina nativos | 197 | 0 | 0 |
| Suites essenciais de cliente/permissões/Planeamento/Subempreitadas/Financeiro/RNC/Viaturas/sessão | 63 | 0 | 4 |
| **Total final, sem somar tentativas intermédias** | **387** | **0** | **4** |

Browser sintético separado: sessão, RNC, Quadro, Medicina e Viaturas PASS, nos formatos desktop/tablet/mobile aplicáveis. As quatro omissões anteriores continuam SKIP. A primeira execução SQL/REST não chegou aos novos casos por falha de disponibilidade do PostgREST local; o executável foi verificado e a execução final completa passou, sem alteração ao produto ou à configuração de produção.

git diff --check: PASS. Busca residual focada existente: ZERO sobre 41 entradas, sem nova busca ampla. A igualdade textual de corpos contra a base confirmou alteração apenas de fn_importar_orcamento_fases; helpers e outras funções permanecem intactos. O rollback é idêntico ao da base.

## Gate seguinte

**GO LOCAL para reauditoria final focada deste P1 e regressão final.** Não é autorização nem confirmação de rollout real. O catálogo/dados atuais do Supabase não foram recapturados; o precheck real continua obrigatório antes de qualquer aplicação futura.

Nenhum SQL foi aplicado em produção, nenhum dado real foi alterado, main foi preservada e Fase B não foi executada. Commit e push destinam-se somente à branch cirúrgica; o SHA final é apresentado na entrega para evitar autorreferência.
