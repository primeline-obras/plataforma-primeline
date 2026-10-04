BEGIN READ ONLY;
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
-- O snapshot integral inclui os 12 writers e as respetivas definições/ACLs anteriores.
DO $economic_inventory$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['fn_concluir_custo_pl(uuid,numeric)','fn_concluir_custo_pl_fase(uuid,numeric)','fn_concluir_custos_pl_tarefa(uuid)','fn_confirmar_custo_real_pl(uuid,numeric)','fn_confirmar_remocao_custo_estimado_subempreitada(uuid)','fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)','fn_eliminar_proposta_comparativo(uuid)','fn_criar_fornecedor_comparativo(uuid,text)','fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)','fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)','fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)','fn_apagar_lancamento_gestao_obras(uuid)'] LOOP
  IF to_regprocedure('public.'||sig) IS NULL THEN RAISE EXCEPTION 'ECONOMIC_WRITER_MISSING: %',sig; END IF;
 END LOOP;
END $economic_inventory$;
-- Segunda ronda: definições e ACLs já incluídas no snapshot integral.
DO $economic_final_inventory$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['fn_confirmar_compromisso_subempreitada(uuid)','fn_importar_orcamento_fases(uuid,jsonb,text)','fn_guardar_precos_candidato_subempreitada(uuid,jsonb)','fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])','fn_adjudicar_candidato_subempreitada(uuid,date,date,text)','fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)','fn_decidir_aditamento_subempreitada(uuid,text,text)','fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)','fn_importar_tees_xlsx(jsonb,text)','fn_importar_tees_revisoes(integer,uuid,jsonb,text)','fn_importar_subempreitadas_xlsx(jsonb,text)','fn_atualizar_venda_contrato_via_tee(uuid)','fn_definir_estado_mensal_v1(uuid,text,text,text,text)','fn_guardar_planeamento_lote(jsonb,text)','fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)'] LOOP
  IF to_regprocedure('public.'||sig) IS NULL THEN RAISE EXCEPTION 'ECONOMIC_WRITER_MISSING: %',sig; END IF;
 END LOOP;
END $economic_final_inventory$;


ROLLBACK;
