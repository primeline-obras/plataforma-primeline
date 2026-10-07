# Security DEFINER — fecho documental e correlatos, 07/10/2026

## Âmbito e evidência

Catálogo real recebido em 07/10/2026: PostgreSQL 17.6, 273 funções e 166 relações. A leitura foi autorizada; não se voltou a consultar a BD real. Este inventário utiliza definições, ACL e schema, sem linhas de negócio.

O scan inclui todas as funções públicas SECURITY DEFINER executáveis por authenticated; procura DML, EXECUTE e chamadas delegadas. Funções RETURNS trigger não são tratadas como RPC invocável: PostgreSQL recusa a chamada direta fora de um trigger. Readers com palavras de DML em comentários também não constituem writers por si só. Foi seguido o caminho de empresa de cada writer documental, incluindo RNC, imóveis/pedidos e frota. Não se afirma certificação universal dos restantes módulos.

## Matriz da classe corrigida

| Função | SECURITY DEFINER | AUTH EXECUTE | Mutação | Tenant guard final | Empresa derivada do ator? | Resultado |
|---|---|---|---|---|---|---|
| `fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)` | SIM | SIM | UPDATE/histórico | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_anexo_imovel(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_anexo_pedido_orcamento(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_anexo_rnc(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_documento_entidade(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_documento_obra(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_imovel_empresa(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_reuniao_condominio(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_apagar_versao_pedido_orcamento(uuid)` | SIM | SIM | DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_cancelar_pedido_orcamento(uuid)` | SIM | SIM | UPDATE/histórico | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_gerir_registo_frota(text,uuid,text,jsonb)` | SIM | SIM | UPDATE/DELETE | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)` | SIM | SIM | UPDATE/histórico | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |
| `fn_registar_documento_obra(uuid,text,text,text)` | SIM | SIM | INSERT | ator ativo + entidade/obra da mesma empresa; locks | SIM | corrigido localmente; baseline real ainda antiga |

São 13 RPCs corrigidas. As capacidades administrativas e de obra continuam a ser verificadas pelas regras originais. Gestão Plataforma mantém capacidade funcional, com tenant obrigatório. Gerência não recebe novas capacidades de Vencimentos. Assinaturas/retornos e lógica de negócio existente foram preservados; exceções de autorização usam 42501.

## Storage

As policies permissivas existentes permanecem. A guarda restritiva cobre os namespaces existentes do bucket documentos (RH, empresa, entidades/imóvel, entidades/pedido, obra) e o prefixo de obra do bucket faturas. SELECT/INSERT/UPDATE/DELETE continuam a depender também da policy original: não se concede nova ação. Não se altera bucket, bytes, path ou objeto. Caminhos malformados, entidades sem empresa e transferências entre empresas são recusados. Outros buckets não são alterados.

## Concorrência e rollback

A RPC de entidades bloqueia o ator FOR SHARE e o documento FOR UPDATE antes de autorizar. Os correlatos bloqueiam target e pais; nos documentos de obra/RNC a obra fica FOR SHARE. A alteração de empresa antes do lock é reavaliada; depois do lock aguarda. Em REPEATABLE READ a atualização concorrente pode provocar serialization failure, sem escrita indevida. Testes com duas ligações observam pg_blocking_pids, sem usar atraso fixo como prova.

O backup conserva definição/owner/ACL/config das 13 RPCs. O rollback de compatibilidade mantém os writers seguros e as policies restritivas; não reintroduz o P1. A certificação instalada inclui todas as RPCs e helpers, owner, ACL e search_path, além do catálogo documental/Storage anterior. Folha precheck compõe apenas este delta certificado com o hotfix já instalado.

## Inventário residual fora da classe documental

Correspondência de hash NÃO é veredito de segurança universal. Os 28 writers económicos e RPCs financeiras são cobertos pelas suites e hotfix anteriores. Os itens abaixo são rastreabilidade do scan, sem ampliar a certificação documental a funcionalidades não relacionadas.

| Função | SD | AUTH EXECUTE | Indicador de DML/delegação | Guardas observadas / enquadramento |
|---|---|---|---|---|
| `fn_adjudicar_candidato_subempreitada(uuid,date,date,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_alertar_subempreitada_execucao_sem_aprovacao()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_apagar_anexo_fatura(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_e_admin, fn_e_administrativo |
| `fn_apagar_compromisso(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin |
| `fn_apagar_guia_fatura(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_e_admin, fn_e_administrativo |
| `fn_apagar_lancamento_gestao_obras(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_mapa_gestao_obras |
| `fn_apagar_reserva_sala(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin, fn_e_administrativo |
| `fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date,text,numeric,text,text,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_medicina_pode_gerir, fn_verificar_alertas_vencimento |
| `fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_medicina_pode_gerir, fn_verificar_alertas_vencimento |
| `fn_atualizar_destinatario_alerta_viatura()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_avancar_estado_fluxo_fatura(uuid,text,date,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_e_admin, fn_utilizador_atual_id |
| `fn_cancelar_rnc(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra |
| `fn_concluir_custo_pl_fase(uuid,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_concluir_custo_pl(uuid,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_concluir_custos_pl_tarefa(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_confirmar_compromisso_subempreitada(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_confirmar_custo_real_pl(uuid,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_confirmar_remocao_custo_estimado_subempreitada(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_criar_alerta_reuniao_semanal(uuid,text,text,date)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_pode_editar_obra |
| `fn_criar_consulta_planeamento(uuid,uuid,text,uuid[],uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | não certificada nesta classe |
| `fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_criar_especialidade_fornecedor(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_criar_fornecedor_comparativo(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_e_admin |
| `fn_criar_reserva_sala(text,date,time without time zone,time without time zone,uuid[])` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id |
| `fn_criar_rnc(uuid,date,uuid,text,text,text,uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_custo_real_ligado(uuid,uuid,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_administrativo, fn_pode_ver_obra |
| `fn_decidir_aditamento_subempreitada(uuid,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_e_admin, fn_utilizador_atual_id |
| `fn_decidir_fatura(uuid,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_decidir_faturacao_auto(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_definir_acao_rnc(uuid,text,text,date)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra |
| `fn_definir_estado_mensal_v1(uuid,text,text,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_e_admin, fn_utilizador_atual_id |
| `fn_definir_zonas_fornecedor(uuid,text[])` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_desmarcar_fatura_paga(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra |
| `fn_devolver_fatura_administrativo(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_financeiro_autorizar_obra, fn_e_admin, fn_pode_editar_obra |
| `fn_devolver_fatura_financeiro(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_financeiro_autorizar_obra, fn_e_admin, fn_e_administrativo |
| `fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_editar_fatura_pendente |
| `fn_editar_fornecedor_diretorio_v2(uuid,text,text,text,text,text,text,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_editar_fornecedor_diretorio |
| `fn_editar_fornecedor_diretorio(uuid,text,text,text,text,text,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_editar_reserva_sala(uuid,text,date,time without time zone,time without time zone,uuid[])` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin, fn_e_administrativo |
| `fn_editar_rnc_base(uuid,date,text,text,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra |
| `fn_eliminar_fornecedor_duplicado(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_eliminar_item_comparativo(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_eliminar_mapa_comparativo(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_eliminar_proposta_comparativo(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_fechar_rnc(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra |
| `fn_guardar_cadastro_fornecedor(uuid,text,text,text,text,text,text,text,text,text[],uuid[],text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id, fn_editar_fornecedor_diretorio_v |
| `fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra |
| `fn_guardar_compromisso(uuid,text,date,time without time zone,time without time zone,boolean,text,uuid,uuid,text,text,text,integer,uuid[])` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin |
| `fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_mapa_gestao_obras, fn_utilizador_atual_id |
| `fn_guardar_planeamento_lote(jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id, fn_pode_editar_obra |
| `fn_guardar_ponto_obra(uuid,uuid,date,text,time without time zone,time without time zone,time without time zone,time without time zone,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin, fn_e_administrativo |
| `fn_guardar_precos_candidato_subempreitada(uuid,jsonb)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_economico_ator_atual, fn_financeiro_autorizar_obra, fn_e_admin, fn_utilizador_atual_id |
| `fn_importar_mapa_gestao(jsonb,boolean)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_utilizador_atual_id |
| `fn_importar_orcamento_fases(uuid,jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_importar_subempreitadas_xlsx(jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_economico_ator_atual, fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_importar_tees_revisoes(integer,uuid,jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_importar_tees_xlsx(jsonb,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_economico_ator_atual, fn_financeiro_autorizar_obra, fn_pode_editar_obra |
| `fn_mapa_gestao_obras_excel()` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_ver_mapa_gestao_obras |
| `fn_mapa_gestao_obras()` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_ver_mapa_gestao_obras, fn_utilizador_atual_id |
| `fn_marcar_fatura_paga(uuid,date)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_marcar_faturacao_auto_paga(uuid,date,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_utilizador_atual_id |
| `fn_mesclar_fornecedor(uuid,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_previsualizar_mesclagem_fornecedor(uuid,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_quadro_operar_v1(text,jsonb,boolean,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id |
| `fn_quadro_operar(text,jsonb,boolean,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id |
| `fn_recalcular_precos_quantidade()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_recalcular_venda_contrato_tee_trigger()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_e_administrativo, fn_e_admin, fn_utilizador_atual_id |
| `fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_financeiro_autorizar_obra |
| `fn_resolver_alerta(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_utilizador_atual_id, fn_e_admin, fn_e_administrativo, fn_pode_editar_obra |
| `fn_resumo_custos_obra(uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_ver_obra, fn_e_administrativo |
| `fn_sincronizar_componente_subempreitada()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_sincronizar_indices_documento_obra()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_sincronizar_tee_planeamento()` | SIM | SIM | trigger; não invocável como RPC | TRIGGER_NON_RPC |
| `fn_validar_justificacao_ponto(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_e_admin, fn_e_administrativo, fn_utilizador_atual_id |
| `fn_verificar_rnc(uuid,text)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_pode_editar_obra, fn_utilizador_atual_id |
| `fn_vincular_fatura_subempreitada(uuid,uuid)` | SIM | SIM | scan de corpo, sujeito a revisão da classe original | fn_financeiro_autorizar_obra, fn_pode_editar_obra, fn_e_admin |
