# Guarda de empresa nos 12 writers económicos — 04/10/2026

## Resultado

**12/12 writers corrigidos e aprovados localmente. GO LOCAL para auditoria final focada deste pacote. NO-GO para declarar todo o domínio económico fechado ou aplicar em produção:** a varredura estática encontrou 14 writers adicionais fora da lista de alteração autorizada, detalhados abaixo.

Base exata: `a3d250820d3d745e5fbeaba1b88117e757803450`, branch `fix/autorizacao-financeira-cross-tenant-20261004`. Branch de entrega: `fix/writers-economicos-tenant-20261004`. A auditoria de referência permanece em `4638db357ca89989d729c0706b7424e340a69054`.

Nenhuma ligação ou escrita na BD real, merge em main, deploy, marker B ou Fase B. Não foram criadas novas técnicas de exploração. As novas provas são testes funcionais defensivos com recursos sintéticos num PostgreSQL local.

## Estratégia

Reutilização de `fn_financeiro_autorizar_obra(obra_real, false)`, sem novo helper nem alteração às seis RPCs já aprovadas. O helper privado verifica auth.uid(), utilizador ativo, empresa não nula, obra existente e igualdade de empresas. Bloqueia o ator e a obra com FOR SHARE durante a transação. Com false não exige papel financeiro; cada writer aplica depois a regra de papel/responsabilidade anterior.

As funções continuam SECURITY DEFINER, owner postgres, com search_path `pg_catalog, public, pg_temp` e EXECUTE somente para authenticated/postgres. A ACL efetiva anterior dos 12 já tinha esses dois papéis; não se ampliou acesso. O helper continua exclusivamente privado ao owner.

O recurso de origem é lido/bloqueado antes da autorização. Componentes resolvem tarefa → fase → obra; tarefas bloqueiam a fase; propostas resolvem e bloqueiam o mapa; lançamentos bloqueiam a linha existente. O escritor de lançamento verifica também a obra de destino em UPDATE e a obra pedida em INSERT. Não utiliza empresa fornecida pelo cliente.

Os vínculos de orçamento/subempreitada de componentes são verificados na mesma obra. A confirmação de remoção do estimado bloqueia os componentes e a hierarquia da tarefa, recusando vínculo a outra obra. A importação de proposta bloqueia o fornecedor e os itens selecionados; a adjudicação bloqueia mapa/proposta/fase/fornecedor e preserva a coerência existente. Uma relação inválida recusa a operação antes de concluir a escrita; o PostgreSQL desfaz também as inserções anteriores da mesma chamada.

Não foram alterados cálculos, estados, valores, alertas ou regras de responsabilidade. A indisponibilidade de tenant e os novos vínculos económicos fora de âmbito devolvem 42501 com mensagem genérica. As validações funcionais existentes, incluindo fase/proposta de outro mapa, conservam os erros de coerência anteriores. Argumentos, defaults e retornos são comparados aos contratos originais.

## Aprovação individual

Cada linha PASS cobre papel legítimo/empresa própria, mesmo papel/outra empresa → 42501, inativo → 42501, empresa nula, identidade sem perfil, papel indevido, recurso inexistente com erro seguro e comparação de estado sem escrita parcial. As operações legítimas verificam os valores/efeitos esperados, não somente ausência de exceção.

| Writer | Resultado | Resolução do recurso |
|---|---|---|
| `fn_concluir_custo_pl(uuid,numeric)` | PASS | componente PL → tarefa → fase |
| `fn_concluir_custo_pl_fase(uuid,numeric)` | PASS | linha orcamento_fases.obra_id |
| `fn_concluir_custos_pl_tarefa(uuid)` | PASS | tarefa → fase |
| `fn_confirmar_custo_real_pl(uuid,numeric)` | PASS | tarefa → fase |
| `fn_confirmar_remocao_custo_estimado_subempreitada(uuid)` | PASS | subempreitada + componentes/tarefas ligados |
| `fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)` | PASS | tarefa → fase + orçamento/subempreitada relacionados |
| `fn_eliminar_proposta_comparativo(uuid)` | PASS | proposta → mapa |
| `fn_criar_fornecedor_comparativo(uuid,text)` | PASS | mapa → obra; fornecedor na empresa da obra |
| `fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)` | PASS | mapa → obra + fornecedor/itens |
| `fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)` | PASS | mapa → obra + proposta/fornecedor/fase |
| `fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)` | PASS | linha original + obra de destino; INSERT separado |
| `fn_apagar_lancamento_gestao_obras(uuid)` | PASS | linha existente → obra |

Gestão/Gerência/Diretor mantêm as operações permitidas nos writers de custos/comparativo dentro da própria empresa. Administrativo/Gestão mantêm lançamento/eliminação no Mapa de Gestão. Não se concedeu lançamento a Gerência/Diretor quando a função anterior não concedia. Os consumidores frontend e os payloads não foram modificados.

## Cinco scripts consolidados

- **Precheck:** mantém fotografia/fingerprint integral anterior, READ ONLY e lista explícita das 12 assinaturas exigidas. Um diagnóstico real atualizado continua obrigatório antes de qualquer autorização futura.
- **Backup:** inclui as 12 definições anteriores, owner, path e ACL no snapshot integral já existente; acrescenta inventário explícito. É backup do catálogo, não das linhas operacionais.
- **Migration:** redefine somente os 12 writers adicionais dentro da transação consolidada, antes de capturar a instalação. Conserva as correções anteriores.
- **Postcheck:** inclui os 12 nas duas listas de alterações permitidas; compara hash dos corpos exatos aprovados, argumentos/defaults/retorno anteriores, owner, SECURITY DEFINER, search_path e ACL exata. Verifica owner/path/ACL privada do helper. Continua READ ONLY, sem invocar writers reais.
- **Rollback:** restaura as 12 definições a partir do backup antes de eliminar o helper; mantém a ACL equivalente e a verificação de drift existente. A suite comprovou restauração do catálogo canónico completo.

O hash MD5 dos corpos serve para detectar drift da definição aprovada; não é mecanismo de autenticação ou hash documental. O inventário local preserva as definições originais e os hashes esperados. Os limites anteriores do fingerprint e a representação ACL implícita/explicita no rollback permanecem documentados; não foram redesenhados nesta correção.

## Testes e regressões

| Grupo | Resultado |
|---|---|
| Autorização/financeiro em PostgreSQL 17.6 + PostgREST 16.4 local, novos writers SQL e testes estáticos | 94 PASS, zero skip |
| Quadro/Cadastro RH/Medicina em PostgreSQL 17.6 | 197 PASS, zero skip |
| 22 ficheiros unitários/estáticos/PGlite | 63 PASS, 4 SKIP, zero fail |
| Browser sessão | 7 cenários PASS |
| Browser RNC | 7 perfis/cenários PASS |
| Browser Quadro | 3 grupos PASS, desktop/tablet/mobile, console limpo |
| Browser Medicina | PASS, quatro perfis/três viewports, operações simuladas |
| Browser Viaturas | PASS, desktop/mobile, operações simuladas |

Total formal Node: **358 testes, 354 PASS, 4 SKIP, zero falhas finais**. Browser é contabilizado separadamente. Os quatro SKIP RH por dependência não foram convertidos em PASS nem alterados.

Cobertura preservada: quatro P0 técnicos, seis RPCs financeiras por HTTP local, alertas de inativos, âmbito do Encarregado, Quadro, RH, Medicina, Financeiro/faturas, Planeamento, comparativos/custos, RNC, documentos, férias/ausências, Viaturas e isolamento de sessão. O teste de duas conexões confirma que uma operação legítima de custo mantém bloqueadas alterações concorrentes da empresa da obra e da atividade do ator. As suites anteriores cobrem replay/concorrência de recebimentos e sessão.

Os novos writers foram exercitados por SQL com SET LOCAL ROLE authenticated e claims sintéticas; não se afirma cobertura HTTP nova de cada um. O harness reconstrói catálogo e instala os triggers já previstos pelas suites; não equivale a reconstruir todas as FKs/defaults/triggers da produção. Os novos defaults/índices necessários aos cenários são locais e revertidos ao fim de cada transação. O teste final compara todas as linhas sintéticas anteriores e o rollback compara todo o catálogo.

Logs locais: `%TEMP%/primeline-writers-security.log`, `primeline-writers-native.log`, `primeline-writers-unit.log`. `git diff --check`: PASS. Nenhum ficheiro frontend foi alterado.

## Varredura residual focada

Foi revista a combinação SECURITY DEFINER + escrita económica + chamadas a `fn_e_admin`, `fn_pode_editar_obra`, `fn_e_diretor_obra` ou `fn_pode_editar_mapa_gestao_obras`, utilizando o snapshot existente e as definições do candidato. Não houve nova varredura dinâmica das 247 funções nem tentativa de bypass.

**Não é possível confirmar “nenhum writer restante sem tenant”.** Foram identificadas as seguintes 14 lacunas estáticas adicionais fora dos 12 autorizados. Mantêm owner postgres e EXECUTE para authenticated no snapshot; a migration não as redefine. Elas utilizam os helpers de papel sem comparar a empresa do ator com a empresa do recurso.

| Assinatura residual | Efeito económico identificado no corpo |
|---|---|
| `fn_confirmar_compromisso_subempreitada(uuid)` | confirma compromisso/custo da tarefa |
| `fn_importar_orcamento_fases(uuid,jsonb,text)` | cria/atualiza orçamento de fase |
| `fn_guardar_precos_candidato_subempreitada(uuid,jsonb)` | substitui preços e total do candidato |
| `fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])` | cria consulta/itens do orçamento |
| `fn_adjudicar_candidato_subempreitada(uuid,date,date,text)` | cria/atualiza adjudicação e consulta |
| `fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)` | cria aditamento económico |
| `fn_decidir_aditamento_subempreitada(uuid,text,text)` | decide aditamento económico |
| `fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)` | conclui subempreitada e substitui avaliação |
| `fn_importar_tees_xlsx(jsonb,text)` | cria TEEs e itens |
| `fn_importar_tees_revisoes(integer,uuid,jsonb,text)` | cria/altera TEEs e histórico/importação |
| `fn_importar_subempreitadas_xlsx(jsonb,text)` | cria consultas/candidatos/subempreitadas |
| `fn_atualizar_venda_contrato_via_tee(uuid)` | atualiza venda contratual efetiva |
| `fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)` | cria/altera ajustes financeiros e débitos |
| `fn_definir_estado_mensal_v1(uuid,text,text,text,text)` | altera estado financeiro mensal e histórico |

Classificação: **P1 por revisão estática**, com efeito dinâmico não reproduzido nesta tarefa. Não se classificam como 14 novos P0 comprovados. Não foram corrigidos porque a lista de alteração autorizada enumera 12 writers e proíbe alterar os workflows adicionais.

O inventário `tests/fixtures/writers-economicos-residual-20261004.json` contém assinaturas, ACL/owner, hashes das definições e classificação; não contém dados reais. A importação do Mapa de Gestão e as funções de cadastro/mesclagem de fornecedores consultadas possuem resolução explícita da empresa; isso não certifica todos os seus ramos ou referências históricas.

## Decisão para a próxima etapa

**GO LOCAL para auditoria independente focada dos 12 corrigidos e do inventário residual.** Os 12 P1 desta implementação estão fechados nas evidências locais disponíveis; nenhum novo P0 foi reproduzido. **NO-GO para produção/fecho global enquanto os 14 P1 residuais não forem tratados ou avaliados numa decisão expressa.** Esta entrega não altera produção nem autoriza rollout.
