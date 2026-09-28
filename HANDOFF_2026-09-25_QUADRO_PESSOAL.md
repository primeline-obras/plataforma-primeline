# HANDOFF — Quadro de Pessoal

Nome solicitado: HANDOFF_2026-09-25_QUADRO_PESSOAL.md. Trabalho retomado/concluído localmente em **28/09/2026**.

## Estado real da entrega

- Branch: `wip/handoff-2026-09-25`.
- HEAD existente ao retomar: `379a79c8cd035046bdb436ffa929931e3cf295f9` (`WIP: checkpoint Primeline GO 2026-09-25`). Esse checkpoint já existia; o agente não o criou nesta implementação.
- **Sem commit, push, merge, deploy ou SQL de produção nesta execução.**
- Implementação e SQLs preparados localmente; **não estão aplicados/publicados**.
- Ao retomar existiam muitas diferenças de fim de linha (CRLF/LF), sem diferenças semânticas pelo `git diff --ignore-space-at-eol`. Foram preservadas, sem reset, checkout destrutivo ou normalização global.
- Estado capturado abaixo antes de adicionar este handoff: 263 entradas em `git status --short`. O próprio handoff acrescenta outra entrada não versionada.
- Há Excel não versionados preexistentes em `docs/`, alheios a esta entrega. Não fazer `git add .` indiscriminadamente.

## Pedido final implementado

1. Qualquer colaborador pode ter várias obras. A flag `permite_multiplas_obras` continua na estrutura por compatibilidade, mas não decide coexistência. Nenhum UPDATE dessa flag.
2. Gestão da Plataforma (`gestao_plataforma`) e ADM (`administrativo`) gerem o quadro. Gerência/DO/Adjunto/Preparador/Desenhador não recebem escrita. Consulta normal preservada.
3. Encarregado sem edição geral: ação exclusiva **Adicionar à minha obra**, destinos obtidos da base e novamente autorizados por perfil ativo + responsabilidade de encarregado + empresa.
4. Pré-visualização obrigatória. Nenhuma origem cria destino; uma origem com período exato move o mesmo ID atomicamente; várias origens ou sobreposição parcial bloqueiam para ADM/Gestão. Destino já existente não duplica nem remove origem.
5. Adicionar, mover e remover distintos; origem administrativa por ID. Não existe mais o fluxo DELETE seguido de POST. Corrigir descrições limita-se aos IDs carregados, com transação/histórico por registo.
6. RLS de escrita restrita, RPC transacional e trigger de proteção também sobre rotas SECURITY DEFINER antigas. Colaboradores, funções de RH e responsabilidades não são modificados pela RPC do quadro.
7. Histórico existente reutilizado, com dados antes/depois, perfil/nome do autor, nome do colaborador, ação e IDs de alocação. Histórico sem escrita pela aplicação; consulta do Encarregado limitada às suas obras. Eventos legados não recebem informação inventada.
8. UI mantém scroll após atualização e lê todas as páginas do histórico mensal, sem truncar na primeira resposta.

## Ficheiros alterados/criados desta entrega

### Aplicação

- `src/app.js`: permissões específicas; ações administrativas por RPC; formulário limitado com pré-visualização; histórico; consulta separada da edição.
- `index.html`: cache-buster app v159 e CSS da nova ação.
- `src/workforce-actions.css`: formulário e detalhes do histórico.
- `src/workforce-policy.js`: capacidades e cliente RPC; este ficheiro **já está no checkpoint 379a79c**, criado no início anterior deste bloco. Não precisa de ser recuperado de /tmp.

### SQLs/documentação

- `supabase/quadro_pessoal_20260925/00_precheck_leitura.sql`
- `supabase/quadro_pessoal_20260925/00_regras_movimentacoes.sql`
- `supabase/quadro_pessoal_20260925/01_prevalidacao.sql`
- `supabase/quadro_pessoal_20260925/02_backup_gravacao.sql`
- `supabase/quadro_pessoal_20260925/03_conferencia.sql`
- `supabase/quadro_pessoal_20260925/manifesto_95.json`
- `supabase/quadro_pessoal_20260925/README.md`
- Este handoff na raiz do repositório.

### Testes

Novos:

- `tests/fixtures/quadro-v3-base.sql`
- `tests/workforce-v3-database.test.mjs`
- `tests/workforce-v3-week.test.mjs`
- `tests/workforce-v3-interface.test.mjs`
- `tests/workforce-v3-dom.test.mjs`
- `tests/quadro-runtime/package.json` e `.gitignore`.

Atualizados porque exigiam regras antigas:

- `tests/foreman-global-workforce-vacations.test.mjs`
- `tests/workforce-admin-only.test.mjs`
- `tests/workforce-allocation-scroll.test.mjs`
- `tests/workforce-foremen-multiple-works.test.mjs`

## Testes executados e resultado

**48 testes, 48 aprovados, 0 falhas** na execução final do conjunto Quadro + matriz de acesso + férias/Encarregado. Tempo reportado pelo runner: ~2,18 s.

- PostgreSQL local em memória (PGlite 0.3.14): execução da migração real em fixture mínima; RLS, triggers, permissões, RPC, duplicados, múltiplas origens, períodos parciais, datas de ausência, versão obsoleta e separação de empresas.
- Movimento com uma origem conserva ID/autor original e insere histórico com autor/perfil da movimentação.
- Falha simulada no trigger de histórico: o movimento é integralmente anulado.
- Função SECURITY DEFINER de teste não contorna a proteção de escrita de DO.
- Gestão/ADM adicionam duas obras com flag false; mover/remover por ID conserva a outra obra.
- Histórico: Encarregado vê somente origem/destino das suas obras; ADM vê geral; UPDATE/DELETE do histórico negados.
- SQLs da semana executados **somente na base local de teste**: 95 posições, João Pedreiro no mesmo ID, 5 férias de Wanderson intactas, nenhuma alocação para ele, flag de Helder e demais flags preservadas, histórico anterior preservado, reexecução idempotente.
- Uma ausência adicional no teste sinaliza apenas a data incompatível, não as cinco datas da pessoa.
- JSDOM: formulário real extraído de app.js exige pré-visualização; mudança da data invalida confirmação; conflito visível; DO não abre a ação; destinos limitados à resposta autorizada.
- `node --check src/app.js` e `node --check src/workforce-policy.js`: aprovados.
- `git diff --check` nos ficheiros editados: sem erros.

Não confundir esses resultados com validação visual em browser ou aplicação em produção: **nenhuma das duas foi feita**. PGlite usa um esquema mínimo, não uma cópia integral da produção, e não houve teste com várias conexões reais simultâneas.

### Como repetir os testes noutro computador

Node 22.16.0 foi usado. Na raiz do repositório:

```sh
npm install --prefix tests/quadro-runtime
node --test tests/workforce-v3-database.test.mjs tests/workforce-v3-week.test.mjs tests/workforce-v3-interface.test.mjs tests/workforce-v3-dom.test.mjs
```

O conjunto final também incluiu todos `tests/workforce-*.test.mjs`, `tests/access-control.test.mjs` e `tests/foreman-global-workforce-vacations.test.mjs`.

Nesta sessão, dependências foram instaladas apenas em `/tmp/quadro-test-runtime`, com `QUADRO_PGLITE`/`QUADRO_JSDOM` a apontar para os módulos. Esses caminhos não são necessários para o outro computador: a instalação versionável está especificada em `tests/quadro-runtime/package.json`.

## Semana: manifesto fechado

- 95 posições, 19 pares pessoa/obra, 16 colaboradores; 28/09–02/10/2026; dia_inteiro.
- Fonte recuperada: exportação `Supabase Snippet Untitled query (18).csv`, com as 100 posições anteriores. Retiradas exclusivamente as cinco do Wanderson, conforme autorização.
- Manoel ausente da automação. Nenhuma semana seguinte.
- João Afonso `81a195a3-d75f-4504-87a7-4060078b9f9e`: Servente → Pedreiro, obrigatório.
- Sem alterações de flags, nomes ou `obra_responsaveis`; múltiplas obras de William/Regivaldo/Helder preservadas.
- Backup `public.quadro_pessoal_20260928_v3_backup`, inacessível à aplicação, inclui estado anterior completo das tabelas em âmbito e estado posterior/IDs inseridos. Nunca sobrescreve silenciosamente um lote divergente.
- Os SQLs antigos que só existiam em `/tmp/quadro_pessoal_20260928` não sobreviveram à mudança de sessão. Os substitutos estão integralmente no repositório.

## Próximos passos exatos — dependem de autorização

1. Rever esta entrega e executar manualmente **somente** `00_precheck_leitura.sql` para confirmar pré-requisitos reais. Se bloquear, não prosseguir nem eliminar dados para passar.
2. Ensaiar `00_regras_movimentacoes.sql` em staging com o esquema real. PostgreSQL >=15 e tabela histórica anterior são pré-requisitos; políticas ALL inesperadas e duplicados abortam sem limpeza automática.
3. Após autorização, aplicar a migração 00 em produção. Nenhum script antigo de permissões/exclusividade deve ser reaplicado depois dela.
4. Executar `01_prevalidacao.sql`, exigir 95/0 bloqueios/PRONTO. Se houver nova ausência/divergência, reportar a posição concreta sem mudar o manifesto silenciosamente.
5. Após confirmação, executar `02_backup_gravacao.sql` e imediatamente `03_conferencia.sql`; exigir CONCLUIDO e verificações verdadeiras.
6. Só então publicar o frontend com autorização explícita. Validar Gestão/ADM/Encarregado/DO em contas reais e o layout num browser.
7. Commit/push/merge não foram autorizados. Para continuar noutro computador, copiar os ficheiros listados ou autorizar a entrega Git posteriormente; este handoff sozinho não transporta o código.

## Decisões/limitações restantes

- Nenhuma decisão funcional pendente nos casos de múltiplas origens: bloqueio para ADM/Gestão, conforme pedido final.
- Ausências mantêm a semântica existente: qualquer registo nessa data bloqueia; não foi redefinido o significado de estados cancelados/rejeitados nem alterada regra do MGO.
- Históricos antigos conservados, mas sem inventar perfis/snapshots que antes não existiam.
- Perfil `gerencia` não está na lista de escrita aprovada. Não foi equiparado a ADM.
- A criação de colaborador com alocação inicial também passa pelo novo trigger; não pode ser usada por perfis não autorizados para contornar o quadro. Não foram concedidos poderes RH ao Encarregado.
- Compatibilidade real em produção, validação visual, concorrência multi-conexão e publicação continuam por confirmar.

## Diferenças semânticas dos ficheiros já versionados

```text
2	1	index.html
127	109	src/app.js
6	5	tests/foreman-global-workforce-vacations.test.mjs
2	2	tests/workforce-admin-only.test.mjs
9	16	tests/workforce-allocation-scroll.test.mjs
12	17	tests/workforce-foremen-multiple-works.test.mjs
```

Os ficheiros novos constam da lista acima e do estado abaixo; não aparecem no numstat de ficheiros já versionados.

## Git status capturado antes de criar este handoff

```text
 M .gitignore
 M README.md
 M assets/brand/logo.svg
 M config.js
 M index.html
 M reset-password/index.html
 M src/access-control.js
 M src/action-plan.js
 M src/app.js
 M src/budget-requests.js
 M src/company-documents.js
 M src/comparative-map.js
 M src/consolidated-view.js
 M src/cost-model.css
 M src/demoData-browser.js
 M src/direct-debits.js
 M src/document-index-pdf.js
 M src/documents.js
 M src/financial-map.js
 M src/meeting-rooms.js
 M src/planning-import.js
 M src/planning.js
 M src/platform-dialogs.js
 M src/procurement.js
 M src/production-dashboard.js
 M src/projects.js
 M src/properties.js
 M src/reset-password.js
 M src/rnc-pdf.js
 M src/rnc.js
 M src/settings.js
 M src/specialties.css
 M src/styles.css
 M src/subcontractors.js
 M src/supabase-browser.js
 M src/supplier-directory-grouping.css
 M src/vehicles.js
 M src/visual-identity-final.js
 M src/visual-phase2.css
 M src/workforce-calendar.css
 M src/xlsx-operational-import.js
 M supabase/aba_ausencias_interface_bloqueios.sql
 M supabase/adjunto_acesso_equipa_tecnica.sql
 M supabase/alerta_primeira_consulta_medicina.sql
 M supabase/alertas_vencimentos_resolucao.sql
 M supabase/alertas_vencimentos_resolucao_corrigido.sql
 M supabase/ativar_log_auditoria.sql
 M supabase/atualizar_obra_120_planeamento_xlsx_20260910.sql
 M supabase/auditoria_rls_permissoes_finais.sql
 M supabase/ausencias_fluxo_permissoes_corrigido.sql
 M supabase/autos_faturacao_aprovacao_pendente.sql
 M supabase/autos_faturacao_workflow.sql
 M supabase/bloco_06_viaturas.sql
 M supabase/bloco_07_contratos_trabalho.sql
 M supabase/bloco_08_faturas_duplicadas.sql
 M supabase/bloco_09_alertas_prioridade_email.sql
 M supabase/bloco_10_cruzamento_rh_obra_financeiro.sql
 M supabase/bloco_12_salas_reuniao.sql
 M supabase/bloco_13_imoveis_orcamentos.sql
 M supabase/cadastro_fornecedor_unificado.sql
 M supabase/centro_documentos_encarregado.sql
 M supabase/classificacao_especialidades_lote_inicial.sql
 M supabase/colaboradores_campos_completos.sql
 M supabase/colaboradores_crud_alocacao_inicial.sql
 M supabase/controlo_versoes_documentos_alerta_subempreitadas.sql
 M supabase/correcoes_pos_auditoria_custos_faturas.sql
 M supabase/correcoes_pos_validacao_encarregado_utilizadores.sql
 M supabase/corrigir_alertas_resolvido_por.sql
 M supabase/corrigir_tees_rsp.sql
 M supabase/custos_estimados_consolidado.sql
 M supabase/custos_estimados_especificacao_final.sql
 M supabase/custos_estimados_modelo_final.sql
 M supabase/custos_obra_automaticos.sql
 M supabase/debitos_diretos_financeiro.sql
 M supabase/definicoes_administracao.sql
 M supabase/documentos_empresa.sql
 M supabase/documentos_obra_workflow.sql
 M supabase/documentos_rh_ativos.sql
 M supabase/eliminacoes_restritas_documentos_imoveis_orcamentos.sql
 M supabase/eliminar_mapa_comparativo.sql
 M supabase/encarregado_quadro_ferias_global.sql
 M supabase/equipa_restringir_ausencias_horas_extra.sql
 M supabase/especialidades_subempreiteiros.sql
 M supabase/faturacao_autos_linhas_discriminadas.sql
 M supabase/faturas_acoes_financeiro_pos_pagamento.sql
 M supabase/faturas_apagar_administrativo.sql
 M supabase/faturas_devolucao_diretor_administrativo.sql
 M supabase/faturas_edicao_pendente_condicao_pagamento.sql
 M supabase/faturas_guias_aviso_temporario.sql
 M supabase/faturas_materiais_descontos.sql
 M supabase/faturas_observacao_aprovacao.sql
 M supabase/faturas_semelhanca_global_empresa.sql
 M supabase/feriados_empresa.sql
 M supabase/fix_quadro_pessoal_multiplos_dias.sql
 M supabase/gestao_plataforma_mapa_orcamento_fases.sql
 M supabase/horas_extraordinarias_permissoes_corrigido.sql
 M supabase/import_obra_120_planeamento_itens.sql
 M supabase/importacao_xlsx_operacional.sql
 M supabase/importar_dados_reais_equipa.sql
 M supabase/indices_pdes_desenhos_pames_pdf.sql
 M supabase/investimentos_impactos_obra.sql
 M supabase/mapa_comparativo_dinamico.sql
 M supabase/mapa_comparativo_editar_eliminar.sql
 M supabase/mapa_comparativo_entrada.sql
 M supabase/mapa_financeiro.sql
 M supabase/mapa_gestao_obras.sql
 M supabase/mapa_gestao_obras_colunas_excel.sql
 M supabase/mgo_grelha_excel_leitura_tecnica.sql
 M supabase/mgo_integridade_datas_filtros.sql
 M supabase/migrar_itens_orcamento_para_fases.sql
 M supabase/modelo_nova_obra.sql
 M supabase/nomes_reais_utilizadores_reunioes.sql
 M supabase/novo_colaborador_rh_conformidade.sql
 M supabase/obra_118_subempreitadas_articulado.sql
 M supabase/parametros_operacionais.sql
 M supabase/pedidos_orcamento_estados_prioridade.sql
 M supabase/pedidos_prorrogacao_indice_pdf.sql
 M supabase/planeamento_consultas_pendentes_especialidades.sql
 M supabase/planeamento_detalhado.sql
 M supabase/plano_acao_encarregado.sql
 M supabase/preencher_fornecedores_fontes_excel.sql
 M supabase/projetos_agrupador_obras.sql
 M supabase/quadro_pessoal_alocacao_diaria.sql
 M supabase/quadro_pessoal_apenas_administrativo_gerencia.sql
 M supabase/quadro_pessoal_encarregados_multiplas_obras.sql
 M supabase/quadro_pessoal_permissoes_corrigido.sql
 M supabase/remover_acesso_financeiro_operacional.sql
 M supabase/rls_ausencias_write_authenticated.sql
 M supabase/rls_authenticated.sql
 M supabase/rls_cashflow_fontes_reais.sql
 M supabase/rls_diretorio_subempreiteiros_authenticated.sql
 M supabase/rls_equipa_authenticated.sql
 M supabase/rls_financeiro_detalhe_obras.sql
 M supabase/rls_obras_authenticated.sql
 M supabase/rls_obras_insert_authenticated.sql
 M supabase/rls_permissoes_finais.sql
 M supabase/rls_quadro_pessoal_write_authenticated.sql
 M supabase/rls_reuniao_producao_authenticated.sql
 M supabase/rls_seguranca_indices_precos.sql
 M supabase/rls_subempreitadas_authenticated.sql
 M supabase/rnc_workflow.sql
 M supabase/salas_reuniao_editar_apagar_notificar.sql
 M supabase/salas_reuniao_listar_participantes.sql
 M supabase/salas_reuniao_participantes_alertas.sql
 M supabase/subempreitadas_mapa_comparativo_workflow.sql
 M supabase/tees_aprovacao_cliente_unica.sql
 M supabase/tees_previsao_encarregados.sql
 M supabase/teste_bloqueio_conclusao_sem_avaliacao.sql
 M supabase/teste_mapa_comparativo_editar_eliminar.sql
 M supabase/viaturas_prazos_edicao.sql
 M supabase/visao_consolidada.sql
 M supabase/visao_geral_final_por_papel.sql
 M supabase/visao_geral_papeis_2026.sql
 M tests/absences-workflow.test.mjs
 M tests/access-control.test.mjs
 M tests/active-collaborators-admission.test.mjs
 M tests/adjunto-access-parity.test.mjs
 M tests/alert-priority-email.test.mjs
 M tests/alert-resolver-user-fk.test.mjs
 M tests/alerts-expiry-resolution.test.mjs
 M tests/audit-log.test.mjs
 M tests/audit-view.test.mjs
 M tests/automatic-work-costs.test.mjs
 M tests/cash-flow-sources.test.mjs
 M tests/classificacao-especialidades-lote-inicial.test.mjs
 M tests/collaborator-complete-fields.test.mjs
 M tests/collaborator-lifecycle.test.mjs
 M tests/collaborator-rh-conformity.test.mjs
 M tests/company-documents.test.mjs
 M tests/comparative-map-dynamic.test.mjs
 M tests/consolidated-view.test.mjs
 M tests/direct-debits.test.mjs
 M tests/document-operational-indexes.test.mjs
 M tests/document-version-subcontract-alert.test.mjs
 M tests/documents-center.test.mjs
 M tests/duplicate-invoice-warning.test.mjs
 M tests/employment-contract-alerts.test.mjs
 M tests/estimated-costs-consolidated.test.mjs
 M tests/estimated-costs-final-model.test.mjs
 M tests/estimated-costs-final.test.mjs
 M tests/extension-requests-index.test.mjs
 M tests/finance-operational-access.test.mjs
 M tests/financial-map.test.mjs
 M tests/foreman-action-plan.test.mjs
 M tests/foreman-global-workforce-vacations.test.mjs
 M tests/global-scroll-safeguard.test.mjs
 M tests/index-filename-convention.test.mjs
 M tests/investment-mode.test.mjs
 M tests/invoice-delete-administrative.test.mjs
 M tests/invoice-director-return-administrative.test.mjs
 M tests/invoice-extraction-editing.test.mjs
 M tests/invoice-finance-actions.test.mjs
 M tests/invoice-guide-warning.test.mjs
 M tests/invoice-observation-approval.test.mjs
 M tests/invoice-pending-detail-approval.test.mjs
 M tests/invoice-pending-edit-payment-condition.test.mjs
 M tests/login-redirect-theme.test.mjs
 M tests/management-map-filters.test.mjs
 M tests/management-map.test.mjs
 M tests/mapa-comparativo.test.mjs
 M tests/material-discounts.test.mjs
 M tests/measurement-billing-approval.test.mjs
 M tests/meeting-alerts.test.mjs
 M tests/meeting-names-adjunct-color.test.mjs
 M tests/meeting-participant-directory.test.mjs
 M tests/meeting-reservations-edit-delete.test.mjs
 M tests/meeting-rooms.test.mjs
 M tests/operational-parameters.test.mjs
 M tests/overtime-workflow.test.mjs
 M tests/overview-final-by-role.test.mjs
 M tests/overview-roles-2026.test.mjs
 M tests/planning-grid-collapsible.test.mjs
 M tests/planning-import.test.mjs
 M tests/planning-obra120-xlsx.test.mjs
 M tests/platform-management-phase-budget.test.mjs
 M tests/post-audit-consolidated.test.mjs
 M tests/post-validation-corrections.test.mjs
 M tests/primeline-go-brand.test.mjs
 M tests/procurement-planning-pending-consultations.test.mjs
 M tests/projects-grouping.test.mjs
 M tests/properties-budget-requests.test.mjs
 M tests/restricted-deletion-paths.test.mjs
 M tests/rh-work-finance-crossing.test.mjs
 M tests/rnc-module.test.mjs
 M tests/rsp-consolidated.test.mjs
 M tests/rsp-tees.test.mjs
 M tests/session-isolation.test.mjs
 M tests/sidebar-directory-final.test.mjs
 M tests/sidebar-icons.test.mjs
 M tests/sidebar-scroll.test.mjs
 M tests/subcontractor-specialties.test.mjs
 M tests/supplier-operational-zones.test.mjs
 M tests/tee-form.test.mjs
 M tests/tees-forecast-foreman.test.mjs
 M tests/ux-obras-alertas-comparativo.test.mjs
 M tests/vehicle-deadlines.test.mjs
 M tests/vehicles-module.test.mjs
 M tests/visual-identity-final.test.mjs
 M tests/visual-phase2.test.mjs
 M tests/work-phases-tab.test.mjs
 M tests/work-template.test.mjs
 M tests/workforce-absence-visual.test.mjs
 M tests/workforce-admin-only.test.mjs
 M tests/workforce-allocation-scroll.test.mjs
 M tests/workforce-foremen-multiple-works.test.mjs
 M tests/workforce-holidays-visual.test.mjs
 M tests/workforce-movements-permissions.test.mjs
 M tests/workforce-vacations.test.mjs
 M tests/works-list-scroll.test.mjs
 M tests/xlsx-operational-import.test.mjs
?? docs/Codigos_RH_Digit_PARA_REVISAO.xlsx
?? docs/Mapa_Gestao_Obras_118_120_122_128_CORRIGIDO.xlsx
?? docs/Mapa_Gestao_Obras_118_120_122_128_DIARIO_MENSAL.xlsx
?? docs/Mapa_Gestao_Obras_118_120_122_128_PARA_IMPORTAR.xlsx
?? docs/fornecedores-comparacao-20260923.xlsx
?? src/workforce-actions.css
?? supabase/quadro_pessoal_20260925/
?? tests/fixtures/
?? tests/quadro-runtime/
?? tests/workforce-v3-database.test.mjs
?? tests/workforce-v3-dom.test.mjs
?? tests/workforce-v3-interface.test.mjs
?? tests/workforce-v3-week.test.mjs
```
