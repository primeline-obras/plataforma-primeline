# Fecho de tenant dos writers económicos — 04/10/2026

Base: `59399e8242a8007cc47bf8ebdd7ede1c94d0fb4f`. Branch: `fix/writers-economicos-tenant-final-20261004`. Nenhuma aplicação em produção autorizada.

## Classificação antes da alteração

A = RPC direta; B = entrada reservada interna; C = RPC e caller interno. A pesquisa incluiu o frontend atual, os corpos das funções e triggers do catálogo capturado, scripts anteriores e a branch urgente para não eliminar contratos legítimos ainda pendentes de integração. Não foi consultado novo catálogo real. Jobs fora do snapshot não estão comprovados.

| Função | Classe | Consumidor e papel funcional anterior |
|---|---|---|
| fn_confirmar_compromisso_subempreitada | A | production-dashboard.js; equipa técnica da obra |
| fn_importar_orcamento_fases | A | xlsx-operational-import.js; Gestão/Diretor |
| fn_guardar_precos_candidato_subempreitada | A | procurement.js; equipa técnica da obra |
| fn_criar_consulta_subempreitada | C | procurement.js e fn_criar_consulta_planeamento; equipa técnica da obra |
| fn_adjudicar_candidato_subempreitada | A | procurement.js; equipa técnica da obra |
| fn_registar_aditamento_subempreitada | A | app.js; equipa técnica/Administrativo/Admin |
| fn_decidir_aditamento_subempreitada | A | app.js; Admin/Gerência/Gestão |
| fn_concluir_subempreitada_com_avaliacao | A | contrato RPC explícito em subempreitadas_mapa_comparativo_workflow.sql; sem ligação frontend atual encontrada; equipa técnica |
| fn_importar_tees_xlsx | A | xlsx-operational-import.js; equipa técnica da obra |
| fn_importar_tees_revisoes | A | tee-index.js e xlsx-operational-import.js na branch urgente; equipa técnica da obra |
| fn_importar_subempreitadas_xlsx | A | xlsx-operational-import.js; equipa técnica da obra |
| fn_atualizar_venda_contrato_via_tee | B | sem consumidor direto ou caller encontrado; retirar canal externo; lógica preservada para owner |
| fn_importar_mapa_financeiro_xlsx | A | xlsx-operational-import.js; Admin/Financeiro |
| fn_definir_estado_mensal_v1 | A | monthly-api.js na branch urgente; Admin/Financeiro |

EXECUTE anterior: authenticated/postgres nos 14, exceto fn_confirmar_compromisso_subempreitada que herda também PUBLIC. Não foram encontrados triggers que chamem diretamente estas 14 funções. O trigger de recálculo da venda TEE utiliza função própria; não é caller de fn_atualizar_venda_contrato_via_tee. A classe B designa a reserva técnica proposta de uma entrada sem consumidor encontrado, não prova de um job existente.

## Pendência estrutural identificada

debitos_diretos não possui empresa_id; despesas gerais usam obra_id NULL. criado_por não é atribuição imutável do tenant do débito e não será usado como substituto silencioso. Decisão expressa da Jordane: bloquear temporariamente o ramo de despesas gerais. Não criar empresa_id, não fazer backfill e não inferir empresa histórica. O bloqueio ocorre na pré-validação integral do payload, com SQLSTATE 0A000 e mensagem DESPESAS_GERAIS_BLOQUEADAS, antes de qualquer ajuste ou log de importação. Linhas de obra continuam a usar a empresa do recurso real. Tipos desconhecidos são recusados com 22023.

## Extensão focada encontrada

fn_guardar_planeamento_lote(jsonb,text) escreve também campos de custo em planeamento_itens e usa fn_pode_editar_obra sem tenant. Corresponde ao padrão autorizado para inclusão nesta mesma tarefa. A correção mantém payload/preview/token/revisão/workflow e acrescenta a guarda de empresa antes do papel/replay.

Também foi encontrada fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean): copia orçamento e tinha uma empresa fixa. A preparação local protege a obra-modelo, deriva a empresa desse recurso autorizado e verifica a empresa do diretor indicado. Ambas as funções adicionais pertencem à mesma classe focada.

## Estado final local

- Os 14 writers pedidos estão preparados, incluindo fn_importar_mapa_financeiro_xlsx com importação por obra protegida e despesas gerais temporariamente bloqueadas.
- Os 12 writers anteriores permanecem protegidos. Total preparado: 26 dos 26 pedidos, mais os dois adicionais encontrados, ou 28 funções.
- O helper fn_atualizar_venda_contrato_via_tee perdeu EXECUTE externo. A chamada pelo owner com contexto autenticado foi testada; não foi inventado consumidor interno ausente do catálogo.
- O novo helper privado fn_economico_ator_atual resolve e bloqueia o ator ativo com empresa; o guard central existente o reutiliza. Não recebe EXECUTE externo.
- As funções de subempreitadas verificam a cadeia real de recursos e IDs relacionados; importadores exercitados recusam payload misto com rollback integral. O estado mensal verifica também a obra do histórico antes de replay.
- Foram corrigidos dois erros técnicos expostos pelo caminho legítimo: SELECT pi.* para preencher o registo composto do compromisso e conversão do número da obra-modelo para o tipo integer real. Nenhuma regra económica foi substituída.
- Precheck, backup, migration, postcheck e rollback consolidados foram atualizados para as funções já preparadas. O importador financeiro integra o inventário, a preservação das ACLs/definições no backup, a verificação exata do corpo no postcheck e a reposição no rollback.

## Evidência local preservada

| Verificação | Resultado |
|---|---|
| PostgreSQL/PostgREST, novos writers, 12 anteriores, RPCs financeiras, P0 anteriores, alertas e rollback; testes estáticos anteriores | 115 PASS, 0 FAIL |
| Quadro/RH e Medicina, PostgreSQL local e concorrência | 197 PASS, 0 FAIL |
| Suites unitárias, estáticas e regressões de módulos | 66 PASS, 4 SKIP, 0 FAIL |
| Browser sintético: sessão, RNC, Quadro, Medicina e Viaturas | PASS |
| git diff --check | PASS |
| Busca focada sobre 41 funções do catálogo capturado com definições locais sobrepostas | ZERO residuais |

Total das suites contadas: 378 PASS e os quatro SKIPs anteriores preservados. Browser é reportado separadamente. Nenhuma escrita real ou chamada a produção foi realizada. As verificações locais não substituem nova confirmação do catálogo real antes de uma aplicação futura.

Limites: o caminho legítimo adicional de planeamento foi exercitado no preview/token; não se afirma confirmação de uma alteração de custo real. O ambiente local não instala todos os triggers de subempreitadas/TEE da produção. Não foi demonstrada a existência de jobs externos ao snapshot.

## Correções por função

| Função | Correção |
|---|---|
| fn_confirmar_compromisso_subempreitada | Cadeia tarefa/fase/subempreitada/obra bloqueada e coerente; empresa antes do papel |
| fn_importar_orcamento_fases | Guarda da obra e fases; payload misto é integralmente rollbackado |
| fn_guardar_precos_candidato_subempreitada | Candidato/consulta/fornecedor/artigos da mesma obra e empresa |
| fn_criar_consulta_subempreitada | Obra autorizada e fase/artigos coerentes; caller existente preservado |
| fn_adjudicar_candidato_subempreitada | Candidato/consulta/fornecedor/fase e subempreitada existente coerentes |
| fn_registar_aditamento_subempreitada | Subempreitada real autorizada e TEE opcional da mesma obra |
| fn_decidir_aditamento_subempreitada | Aditamento/subempreitada/TEE coerentes e autorizados |
| fn_concluir_subempreitada_com_avaliacao | Obra real autorizada antes da regra de conclusão/avaliação |
| fn_importar_tees_xlsx | Ator ativo; cada obra/fase autorizada; atomicidade integral |
| fn_importar_tees_revisoes | Pré-validação de todos os recursos antes de importar ou devolver replay |
| fn_importar_subempreitadas_xlsx | Ator ativo; cada obra/fase/fornecedor coerente; atomicidade integral |
| fn_atualizar_venda_contrato_via_tee | TEE/obra autorizados; EXECUTE externo removido |
| fn_importar_mapa_financeiro_xlsx | Todas as obras validadas antes da escrita; despesas gerais recusadas com 0A000 |
| fn_definir_estado_mensal_v1 | Obra e histórico/replay autorizados antes da escrita/resposta |

O teste de despesas gerais cobre as três categorias, isoladas e antes/depois de uma linha de obra. Confirma erro funcional claro e igualdade de todas as tabelas sintéticas depois da recusa. O importador por obra cobre papel legítimo, outra empresa, inativo, ator sem empresa, papel indevido, recurso inexistente e payload misto. Nenhuma estrutura ou linha histórica de debitos_diretos foi modificada.

## Fecho e limites

GO LOCAL para auditoria final focada: 26/26 writers pedidos mais dois adicionais protegidos; ZERO residuais na busca especificada. Nenhum novo P0 ou P1 confirmado nesta classe pelos testes locais. Despesas gerais constituem exceção funcional temporária explícita, autorizada; a reabertura exige modelo de tenant próprio e reconciliação posterior.

Nenhum SQL foi aplicado em produção. Main, marker B e Fase B permanecem sem alteração por esta tarefa. Commit e push destinam-se exclusivamente à branch fix/writers-economicos-tenant-final-20261004; o SHA final é apresentado no relatório de entrega para evitar autorreferência no documento.
