-- Restaura só a alteração desta entrega. Sem CASCADE; conserva o backup privado.
BEGIN;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.colaboradores, public.subempreitadas, public.ausencias, public.fornecedores, public.fornecedores_aliases, public.fornecedores_mesclagens, public.avaliacoes_subempreiteiro, public.quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE;
DO $private$
BEGIN
 IF (SELECT nspowner<> 'postgres'::regrole FROM pg_namespace WHERE nspname='primeline_encarregado_20261004')
 OR NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_encarregado_20261004') THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<> 'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
 IF (SELECT count(*) FROM primeline_encarregado_20261004.snapshot)<>1
 OR (SELECT md5(catalogo::text) FROM primeline_encarregado_20261004.snapshot)<>'2be961099e9694bdd29ba95d3cc10173' THEN RAISE EXCEPTION 'BACKUP_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute x JOIN pg_class c ON c.oid=x.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(x.attacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
END $private$;
DO $rollback$
DECLARE actual jsonb; installed jsonb; def text;
BEGIN
 actual:=(SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',(SELECT array_agg(acl_item::text ORDER BY acl_item::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) acl_item),'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 SELECT catalogo INTO installed FROM primeline_encarregado_20261004.instalacao;
 IF installed IS NULL OR actual IS DISTINCT FROM installed THEN RAISE EXCEPTION 'ROLLBACK_DRIFT: requer revisão humana'; END IF;
 SELECT f->>'definition' INTO def FROM primeline_encarregado_20261004.snapshot b CROSS JOIN LATERAL jsonb_array_elements(b.catalogo->'functions') f WHERE f->>'signature'='fn_quadro_contexto_v1(date,date)';
 IF def IS NULL THEN RAISE EXCEPTION 'BACKUP_FUNCTION_MISSING'; END IF;
 EXECUTE def;
FOR def IN SELECT f->>'definition' FROM primeline_encarregado_20261004.snapshot b CROSS JOIN LATERAL jsonb_array_elements(b.catalogo->'functions') f
 WHERE f->>'signature' IN('fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()','fn_quadro_operar(text,jsonb,boolean,text)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid)','fn_custo_real_ligado(uuid,uuid,uuid)','fn_marcar_fatura_paga(uuid,date)','fn_desmarcar_fatura_paga(uuid)','fn_devolver_fatura_financeiro(uuid,text)','fn_avancar_estado_fluxo_fatura(uuid,text,date,text)','fn_marcar_faturacao_auto_paga(uuid,date,numeric)','fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)','fn_resolver_alerta(uuid)','fn_decidir_fatura(uuid,text,text)','fn_decidir_faturacao_auto(uuid,text)','fn_devolver_fatura_administrativo(uuid,text)','fn_vincular_fatura_subempreitada(uuid,uuid)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)','fn_apagar_guia_fatura(uuid)','fn_apagar_anexo_fatura(uuid)','fn_eliminar_mapa_comparativo(uuid)','fn_eliminar_item_comparativo(uuid)','fn_concluir_custo_pl(uuid,numeric)','fn_concluir_custo_pl_fase(uuid,numeric)','fn_concluir_custos_pl_tarefa(uuid)','fn_confirmar_custo_real_pl(uuid,numeric)','fn_confirmar_remocao_custo_estimado_subempreitada(uuid)','fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)','fn_eliminar_proposta_comparativo(uuid)','fn_criar_fornecedor_comparativo(uuid,text)','fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)','fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)','fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)','fn_apagar_lancamento_gestao_obras(uuid)','fn_confirmar_compromisso_subempreitada(uuid)','fn_importar_orcamento_fases(uuid,jsonb,text)','fn_guardar_precos_candidato_subempreitada(uuid,jsonb)','fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])','fn_adjudicar_candidato_subempreitada(uuid,date,date,text)','fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)','fn_decidir_aditamento_subempreitada(uuid,text,text)','fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)','fn_importar_tees_xlsx(jsonb,text)','fn_importar_tees_revisoes(integer,uuid,jsonb,text)','fn_importar_subempreitadas_xlsx(jsonb,text)','fn_atualizar_venda_contrato_via_tee(uuid)','fn_definir_estado_mensal_v1(uuid,text,text,text,text)','fn_guardar_planeamento_lote(jsonb,text)','fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)') LOOP EXECUTE def; END LOOP;
END $rollback$;
DROP POLICY financeiro_empresa_insert ON public.faturas_itens;
DROP POLICY financeiro_empresa_insert ON public.faturas_anexos;
DROP POLICY financeiro_empresa_insert ON public.faturas_guias;
DROP POLICY financeiro_empresa_update ON public.faturas_guias;
DROP POLICY financeiro_empresa_delete ON public.faturas_guias;
DROP POLICY financeiro_empresa_insert ON public.mapas_comparativos;
DROP POLICY financeiro_empresa_update ON public.mapas_comparativos;
DROP POLICY financeiro_empresa_delete ON public.mapas_comparativos;
DROP POLICY financeiro_empresa_insert ON public.comparativo_itens;
DROP POLICY financeiro_empresa_update ON public.comparativo_itens;
DROP POLICY financeiro_empresa_delete ON public.comparativo_itens;
DROP POLICY financeiro_empresa_insert ON public.comparativo_propostas;
DROP POLICY financeiro_empresa_update ON public.comparativo_propostas;
DROP POLICY financeiro_empresa_delete ON public.comparativo_propostas;
DROP POLICY financeiro_empresa_insert ON public.comparativo_ajustes;
DROP POLICY financeiro_empresa_update ON public.comparativo_ajustes;
DROP POLICY financeiro_empresa_delete ON public.comparativo_ajustes;
DROP POLICY financeiro_empresa_insert ON public.comparativo_itens_precos;
DROP POLICY financeiro_empresa_update ON public.comparativo_itens_precos;
DROP POLICY financeiro_empresa_delete ON public.comparativo_itens_precos;
REVOKE ALL ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_apagar_guia_fatura(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_guia_fatura(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_apagar_guia_fatura(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_fatura(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_fatura(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_fatura(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_eliminar_mapa_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_mapa_comparativo(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_mapa_comparativo(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_eliminar_item_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_item_comparativo(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_eliminar_item_comparativo(uuid) TO authenticated;
DROP POLICY financeiro_empresa_insert ON public.faturas;
DROP POLICY financeiro_empresa_delete ON public.faturas;
DROP POLICY financeiro_empresa_insert ON public.faturacao;
DROP POLICY financeiro_empresa_delete ON public.faturacao;
DROP FUNCTION public.fn_financeiro_obra_da_empresa(uuid);
REVOKE ALL ON FUNCTION public.fn_decidir_fatura(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_decidir_fatura(uuid,text,text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_decidir_fatura(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_decidir_faturacao_auto(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_decidir_faturacao_auto(uuid,text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_decidir_faturacao_auto(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_administrativo(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_vincular_fatura_subempreitada(uuid,uuid) TO authenticated;
DROP POLICY alertas_sessao_ativa ON public.alertas;
DROP FUNCTION public.fn_financeiro_autorizar_obra(uuid,boolean);
DROP FUNCTION public.fn_economico_ator_atual();
-- A ACL PUBLIC anterior de compromisso é preservada no rollback aprovado.
REVOKE ALL ON FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_confirmar_compromisso_subempreitada(uuid) TO postgres;
REVOKE ALL ON FUNCTION public.fn_atualizar_venda_contrato_via_tee(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_atualizar_venda_contrato_via_tee(uuid) TO authenticated,postgres;
DROP FUNCTION public.fn_autorizacao_sessao_ativa();
REVOKE ALL ON FUNCTION public.fn_marcar_fatura_paga(uuid,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_marcar_fatura_paga(uuid,date) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_marcar_fatura_paga(uuid,date) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_desmarcar_fatura_paga(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_desmarcar_fatura_paga(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_desmarcar_fatura_paga(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_devolver_fatura_financeiro(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_marcar_faturacao_auto_paga(uuid,date,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_resolver_alerta(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolver_alerta(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_resolver_alerta(uuid) TO authenticated;
DROP POLICY encarregado_sem_select_direto ON public.colaboradores;
DROP POLICY encarregado_sem_select_direto ON public.subempreitadas;
DROP FUNCTION public.fn_subempreitadas_operacionais_obra(uuid);
DROP POLICY encarregado_sem_select_direto ON public.ausencias;
DROP POLICY encarregado_sem_select_direto ON public.fornecedores;
DROP POLICY encarregado_sem_select_direto ON public.fornecedores_aliases;
DROP POLICY encarregado_sem_select_direto ON public.fornecedores_mesclagens;
DROP POLICY encarregado_sem_select_direto ON public.avaliacoes_subempreiteiro;
DROP POLICY encarregado_sem_dml_direto ON public.quadro_pessoal_alocacao;
DROP FUNCTION public.fn_ausencias_equipa_encarregado(date,date);
DROP FUNCTION public.fn_encarregado_acesso_direto_bloqueado();
REVOKE ALL ON FUNCTION public.fn_ajustar_saida_prevista_mensal(uuid,date,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_ajustar_saida_prevista_mensal(uuid,date,numeric) TO PUBLIC;
REVOKE ALL ON FUNCTION public.fn_atualizar_melhor_preco_comparativo(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_atualizar_melhor_preco_comparativo(uuid) TO PUBLIC;
REVOKE ALL ON FUNCTION public.fn_congelar_planeamento_baseline(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_congelar_planeamento_baseline(uuid) TO PUBLIC;
REVOKE ALL ON FUNCTION public.fn_verificar_congelamentos_pendentes() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_verificar_congelamentos_pendentes() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_quadro_ferias_encarregado_global(date,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid) TO authenticated;
-- Fotografia real de 04/10/2026. Apenas catálogo; sem dados de produção no ficheiro.
DO $check$
DECLARE v jsonb;
BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF current_setting('server_version_num')::integer / 10000 <> 17 THEN RAISE EXCEPTION 'SERVER_MAJOR_DRIFT'; END IF;
 v := (SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',(SELECT array_agg(acl_item::text ORDER BY acl_item::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) acl_item),'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 IF md5(v::text) <> '2be961099e9694bdd29ba95d3cc10173' THEN RAISE EXCEPTION 'CATALOG_DRIFT: interromper e repetir diagnóstico'; END IF;
END $check$;

DROP TABLE primeline_encarregado_20261004.instalacao;
COMMIT;
