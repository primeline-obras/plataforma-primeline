# Auditoria final focada do hotfix de autorização económica

Data: 04/10/2026. Candidato: `fix/writers-economicos-tenant-final-20261004`, SHA `c79b6e406005c92077d358c1d4502d3bb34c125f`.

Branch independente: `audit/writers-economicos-tenant-final-20261004`, criada exatamente nesse SHA após confirmar o remoto e working tree limpo. O SHA do commit de auditoria é entregue na resposta; não é incluído neste documento para evitar autorreferência.

## Parecer

**NO-GO para rollout real: um P1 confirmado localmente em fn_importar_orcamento_fases.** O candidato permanece intacto; nenhuma correção foi aplicada.

- 27/28 writers: PASS nas verificações executadas; fn_importar_orcamento_fases: FAIL no caso de coerência do alvo existente.
- Busca residual focada: ZERO, sobre 41 funções que correspondem ao filtro da classe.
- Nenhum P0 novo confirmado; um P1 confirmado nesta classe por revisão e teste local de coerência.
- 378 PASS / 2 FAIL / 4 SKIP; browser PASS, contado separadamente.
- O candidato, os cinco scripts SQL e o frontend não foram corrigidos ou alterados nesta auditoria.
- Nenhuma consulta ou escrita de produção foi executada. Nenhum merge, publicação, marker B ou Fase B.

O parecer valida o pacote no catálogo capturado e no ambiente sintético. Não afirma que o catálogo de produção foi novamente consultado nesta ronda, nem autoriza aplicar a migration.

## Método e preservação

Revisão dos corpos e das diferenças do candidato, contratos de consumidores, ACLs, owner/search_path, cadeia de recursos e ordem das guardas; reexecução das suites defensivas existentes em PostgreSQL 17.6/PostgREST locais. O catálogo real capturado anteriormente foi reconstruído sem dados reais. Não houve novas técnicas de exploração nem procura fora da classe autorizada.

As guardas novas derivam o ator de auth.uid(), exigem ativo IS TRUE e empresa não nula, bloqueiam o ator com FOR SHARE e resolvem a empresa pela obra real, também bloqueada. A comparação de empresa antecede a autorização funcional do writer. Recursos relacionados são verificados e bloqueados conforme a cadeia aplicável. Payloads/importadores que processam linhas sequencialmente continuam numa única chamada/transação, sem capturar erros para confirmar partes do lote.

Foram acrescentadas duas verificações funcionais de auditoria: confirmação efetiva de valor_estimado pelo contrato de preview/token de Planeamento e replay idempotente (PASS), e coerência da empresa do orçamento de fase já existente no alvo do upsert (FAIL). Esta segunda verificação usa o mesmo padrão de recurso relacionado incoerente das suites anteriores, sem nova técnica de bypass. Ambas usam dados sintéticos e ROLLBACK integral. Nenhuma regra de produto foi corrigida.

## 28 writers

PASS combina revisão de origem do tenant, contratos/ACLs e testes locais; não se aplica ao writer com o P1 descrito abaixo. Para entidades relacionadas que violam coerência, a recusa pode manter o erro funcional anterior; não se afirma que toda validação de conteúdo devolve 42501. A guarda de acesso a obra de outra empresa devolve 42501.

| Writer | Estado | Evidência principal |
|---|---|---|
| fn_concluir_custo_pl | PASS | Componente → tarefa → fase → obra; tenant antes do papel |
| fn_concluir_custo_pl_fase | PASS | Resumo/fase/obra autorizado e bloqueado |
| fn_concluir_custos_pl_tarefa | PASS | Tarefa/fase autorizadas; conclusão preservada |
| fn_confirmar_custo_real_pl | PASS | Recurso real e empresa antes da confirmação |
| fn_confirmar_remocao_custo_estimado_subempreitada | PASS | Subempreitada e componentes relacionados coerentes |
| fn_guardar_componente_custo | PASS | Tarefa, artigo e subempreitada da obra autorizada |
| fn_eliminar_proposta_comparativo | PASS | Proposta → mapa → obra |
| fn_criar_fornecedor_comparativo | PASS | Empresa derivada da obra/mapa autorizado |
| fn_importar_proposta_comparativo | PASS | Mapa, fornecedor e artigos coerentes; rollback de erro |
| fn_criar_subempreitada_do_comparativo | PASS | Mapa, proposta, fornecedor e fase coerentes |
| fn_guardar_lancamento_gestao_obras | PASS | Recurso existente e obra de destino autorizados |
| fn_apagar_lancamento_gestao_obras | PASS | Obra do lançamento real antes de eliminar |
| fn_confirmar_compromisso_subempreitada | PASS | Tarefa/fase/subempreitada da mesma obra |
| fn_importar_orcamento_fases | **FAIL / P1** | Obra/fase do payload autorizadas, mas alvo existente do upsert não tem tenant validado |
| fn_guardar_precos_candidato_subempreitada | PASS | Candidato/consulta/artigos/fornecedor coerentes |
| fn_criar_consulta_subempreitada | PASS | Fase e artigos da obra; caller existente preservado |
| fn_adjudicar_candidato_subempreitada | PASS | Consulta, fornecedor, fase e subempreitada coerentes |
| fn_registar_aditamento_subempreitada | PASS | Subempreitada/TEE da obra autorizada |
| fn_decidir_aditamento_subempreitada | PASS | Aditamento/subempreitada/obra/TEE coerentes |
| fn_concluir_subempreitada_com_avaliacao | PASS | Obra real antes de conclusão e avaliação |
| fn_importar_tees_xlsx | PASS | Cada obra/fase autorizada; lote misto revertido |
| fn_importar_tees_revisoes | PASS | Todos os recursos prevalidam; replay autorizado |
| fn_importar_subempreitadas_xlsx | PASS | Cada obra/fase/fornecedor; lote misto revertido |
| fn_atualizar_venda_contrato_via_tee | PASS | Owner técnico; TEE/obra/tenant; sem canal externo |
| fn_importar_mapa_financeiro_xlsx | PASS | Obras prevalidadas; despesas gerais bloqueadas |
| fn_definir_estado_mensal_v1 | PASS | Obra atual e histórico/replay autorizados |
| fn_guardar_planeamento_lote | PASS | Tenant antes de preview/token/replay; custo confirmado e replay testados |
| fn_criar_obra_de_modelo | PASS | Modelo autorizado; nova empresa derivada do recurso; diretor coerente |

As suites dos 12 primeiros e dos 16 restantes exercitam chamadas legítimas, outra empresa, inativo, papel errado, recurso inexistente e ausência de efeitos parciais. Os testes de relações abrangem as cadeias aplicáveis e casos preparados; não constituem enumeração de todas as combinações possíveis de argumentos.

## Helpers e consumidores

- fn_atualizar_venda_contrato_via_tee: ACL efetiva somente postgres. anon/authenticated/service_role não têm EXECUTE. O owner, com contexto autenticado legítimo, continua a calcular a venda; a guarda TEE → obra → empresa permanece no corpo. Não foi encontrado caller ativo direto, trigger ou job que dependa dessa entrada. O trigger de recálculo TEE utiliza outra função; não foi inventado um job consumidor.
- fn_economico_ator_atual: privado, owner postgres, SECURITY DEFINER e search_path=pg_catalog; exige ator ativo e empresa. PUBLIC/anon/authenticated/service_role não recebem EXECUTE.
- fn_financeiro_autorizar_obra: permanece privado e mantém a regra específica de pagamento. As seis RPCs financeiras existentes passaram novamente em SQL/PostgREST local.
- Contratos de parâmetros/defaults/retorno das 28 funções permanecem iguais aos originais capturados. Os corpos e ACLs instalados correspondem ao inventário aprovado e aos hashes do postcheck.
- Consumidores diretos e históricos documentados foram revistos, incluindo os contratos da branch urgente de TEE/estado mensal. fn_criar_consulta_planeamento continua a chamar a consulta guardada antes da escrita seguinte. Os testes de cliente/browser são sintéticos; não foi feita importação real pelo frontend.

## Despesas gerais e importadores

fn_importar_mapa_financeiro_xlsx verifica o payload inteiro antes de gravar em mapa_financeiro_ajustes ou chamar fn_log_importacao_xlsx. tipo=despesa_fixa provoca SQLSTATE 0A000 com DESPESAS_GERAIS_BLOQUEADAS. O corpo deixa de escrever em debitos_diretos/debitos_diretos_lancamentos. Não cria empresa_id nem infere propriedade a partir de criado_por.

As três categorias de despesas foram testadas isoladamente e antes/depois de uma linha legítima de obra. Todos os casos recusaram sem alterações, incluindo sem log parcial. A importação por obra da própria empresa foi permitida; obra estrangeira e payload misto foram recusados integralmente.

Os cinco importadores de fases, TEE simples, revisões TEE, subempreitadas e mapa financeiro passaram nos casos existentes de atomicidade de payload misto. Isso não fecha o caso adicional de tenant do alvo existente em fn_importar_orcamento_fases, que falhou. No importador de fases e nos importadores simples, a atomicidade da chamada reverte eventuais alterações anteriores à linha recusada; no mapa financeiro e na pré-validação de revisões TEE, os recursos são verificados antes da primeira escrita.

## Busca residual independente

Reexecutei a busca existente sem alterar o filtro: SECURITY DEFINER + escrita económica + EXECUTE externo + guarda de papel sem tenant explícito. Resultado: 41 entradas analisadas, ZERO residuais. O helper de venda TEE é a entrada interna sem EXECUTE externo.

A revisão não aceitou apenas o nome da guarda ou a presença de empresa_id. Foram lidas as guardas centrais e as seleções de recurso das funções. As cinco entradas legadas que o filtro marca com proteção própria foram revistas no código: mesclar/eliminar fornecedor, importar mapa de gestão, editar diretório e guardar cadastro; selecionam os recursos pela empresa do ator. Não foram reabertos testes gerais dessas funções fora do delta.

ZERO é o resultado textual dessa classe/filtro no catálogo capturado sobreposto com o candidato. A busca reconhece a guarda central no corpo, mas não prova a autorização de cada alvo de escrita. O P1 confirmado demonstra essa limitação: a existência da chamada de tenant não basta para declarar a classe fechada.

## Cinco scripts de rollout

| Script | Resultado | Evidência |
|---|---|---|
| encarregado_escopo_precheck.sql | PASS | BEGIN READ ONLY; owner/major; fingerprint de funções, contratos, ACLs, policies, colunas e views; drift de grant/policy/definer aborta |
| encarregado_escopo_backup.sql | PASS | Snapshot integral de catálogo e ACLs brutas, incluindo 28 writers; schema privado e RLS; sem linhas operacionais |
| encarregado_escopo_migration.sql | PASS estrutural / **NO-GO funcional** | Transação e locks; exige catálogo/backup esperado; não executa importadores nem migra linhas económicas; guards/ACLs previstos |
| encarregado_escopo_postcheck.sql | PASS estrutural / **insuficiente para o P1** | Somente leitura; definições, ACLs, owner/path, helpers e hashes dos 28; catálogo fora da lista autorizado preservado; drift posterior recusado |
| encarregado_escopo_rollback.sql | PASS | Restaura corpos e privilégios anteriores; remove helpers/policies novos sem CASCADE; catálogo e acesso anteriores recuperados no teste local |

O postcheck verifica os hashes dos corpos dos 28 writers e o catálogo instalado; a busca textual focada é executada localmente, não há uma nova exploração genérica no postcheck de produção. O backup é de catálogo, não um novo backup de dados operacionais. Os cinco scripts executam e o rollback funciona no ensaio local, mas a migration ainda instala o writer com o P1. O precheck não verifica a coerência das linhas obra_id/fase_id de orcamento_fases e o postcheck não exercita esse alvo de upsert. Portanto, o conjunto não está apto para rollout funcional seguro sem correção e nova auditoria desse ponto.

O fingerprint não inclui toda a estrutura operacional: defaults, nullability, constraints, índices e triggers não são todos capturados por essa expressão. As fixtures reconstruídas também não reproduzem todos esses elementos; os cenários instalam os elementos necessários e triggers selecionados. Não foi identificado drift nesses elementos nesta auditoria local, mas não se afirma reconfirmação real. O rollout deve respeitar o precheck contra a fotografia prevista e parar se divergir, sem adaptar SQL em produção.

## Testes e regressões

| Grupo | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Segurança SQL/PostgREST, 28 writers, testes adicionais, seis RPCs financeiras, P0 anteriores, helpers, RLS, scripts e testes estáticos | 118 | 2 | 0 |
| Quadro/RH e Medicina nativos, incluindo concorrência e rollback | 197 | 0 | 0 |
| Clientes, permissões, faturas, subempreitadas, Planeamento, RH, alertas, documentos, RNC, Viaturas e sessão | 63 | 0 | 4 |
| **Total contado, sem somar reexecuções intermédias** | **378** | **2** | **4** |

As duas falhas contabilizadas são um único caso funcional negativo e a sua suite-pai, não dois achados independentes. As 378 aprovações da execução final e os quatro SKIPs foram preservados.

Browser separado: sessão/isolamento, RNC, Quadro controlado, Medicina e Viaturas PASS. Desktop/tablet/mobile são cobertos nos cenários existentes aplicáveis; console limpo nesses testes. Todo o tráfego externo desses browsers é interceptado. As quatro omissões anteriores continuam SKIP, sem serem convertidas em PASS; não equivalem a novas falhas de produto.

git diff --check: PASS. A alteração desta branch contém apenas teste, ligação à suite e este relatório. Os cinco scripts e os ficheiros de produto permanecem idênticos ao SHA candidato.

## P1 confirmado — alvo existente do importador de fases

**P1-01: fn_importar_orcamento_fases autoriza a fase recebida, mas não o orçamento existente atualizado por ON CONFLICT(fase_id).**

Localização: supabase/encarregado_escopo_migration.sql:2737–2752. A função verifica a empresa de p_obra_id e exige que fases.obra_id corresponda a essa obra. Depois insere em orcamento_fases e, havendo conflito por fase_id, atualiza valores económicos sem verificar a obra_id do registo que já existe. A atualização não substitui obra_id, deixando o alvo na empresa anterior.

Pré-condição do achado: existe uma linha de orcamento_fases com obra_id de outra empresa e fase_id da obra autorizada. A definição de tabela em supabase/gestao_plataforma_mapa_orcamento_fases.sql contém FKs independentes para obra e fase, além de UNIQUE(fase_id), sem impor a igualdade entre as duas obras. O snapshot de triggers dessa tabela contém apenas auditoria. Não foi verificada a existência dessa incoerência em produção nesta ronda, nem foi recapturado o catálogo real de constraints.

Evidência local: o cenário sintético manteve a fase na empresa A e o orçamento existente com obra_id da empresa B. O ator legítimo da empresa A chamou o importador; a chamada foi aceite e custo_total_estimado mudou de 10 para 77 no alvo, mantendo obra_id da empresa B. Era esperada recusa 42501. O teste falhou e a transação completa foi revertida. Os testes posteriores confirmaram todas as tabelas sintéticas originais intactas.

Teste: tests/writers-economicos-final-audit-cases.mjs, cenário “audit: budget phase importer refuses an existing target belonging to another company”. O teste falhado é preservado na branch de auditoria; não foi ajustado para aprovar o comportamento atual.

Correção recomendada para tarefa separada: autorizar e bloquear também o alvo existente de orcamento_fases antes do upsert, recusar qualquer divergência de obra e garantir que a condição se mantém na escrita concorrente. Não mover, reatribuir ou corrigir linhas históricas automaticamente. Preservar rollback total do lote e adicionar a verificação de coerência necessária ao precheck. Nenhuma dessas mudanças foi implementada nesta auditoria.

## Decisão operacional

P0: nenhum novo confirmado nesta classe. P1: um confirmado localmente, sob a pré-condição descrita. Regressões das suites existentes: nenhuma nova; o caso adicional de coerência falhou. Não houve validação bloqueada pela proteção do ambiente nesta ronda.

Limites: não houve ensaio com dados reais nem reconfirmação atual do Supabase; os SKIPs permanecem; não foi comprovado job externo ao snapshot; despesas gerais estão indisponíveis por decisão expressa. Não se declara que o P1 tenha afetado dados reais.

**NO-GO PARA ROLLOUT REAL DO CANDIDATO c79b6e406005c92077d358c1d4502d3bb34c125f.** Corrigir o P1 em tarefa separada e repetir o gate focado. Main, candidato e produção permanecem preservados.
