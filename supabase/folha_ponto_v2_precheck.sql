-- REAL CATALOG VALIDATION REQUIRED: herda integralmente o postcheck auditado do hotfix.
-- Somente leitura. Verifica instalação e preservação integral do catálogo fora da lista autorizada.
BEGIN READ ONLY;
DO $adm_sources$ BEGIN
 IF to_regclass('public.ausencias_anexos') IS NULL OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.ausencias_anexos'::regclass AND attname='ausencia_id' AND atttypid='uuid'::regtype AND NOT attisdropped)
 OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.ausencias_anexos'::regclass AND attname='arquivo_url' AND atttypid='text'::regtype AND NOT attisdropped)
 OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.colaboradores'::regclass AND attname='funcao' AND atttypid='text'::regtype AND NOT attisdropped)
 THEN RAISE EXCEPTION 'ADM_SOURCE_SCHEMA_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.ausencias_anexos an LEFT JOIN public.ausencias a ON a.id=an.ausencia_id WHERE a.id IS NULL) THEN RAISE EXCEPTION 'ABSENCE_ATTACHMENT_ORPHAN'; END IF;
END $adm_sources$;
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
-- Read-only integrity gate: report identifiers only; never reconcile automatically.
DO $budget_phase_coherence$
DECLARE divergencias jsonb;
BEGIN
 SELECT jsonb_agg(jsonb_build_object(
   'orcamento_fase_id',o.id,'fase_id',o.fase_id,
   'obra_orcamento_id',o.obra_id,'obra_fase_id',f.obra_id) ORDER BY o.id)
 INTO divergencias
 FROM public.orcamento_fases o LEFT JOIN public.fases f ON f.id=o.fase_id
 WHERE f.id IS NULL OR o.obra_id IS DISTINCT FROM f.obra_id;
 IF divergencias IS NOT NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',
   MESSAGE='ORCAMENTO_FASES_OBRA_DIVERGENTE: interromper e reconciliar manualmente; nenhum registo foi corrigido.',
   DETAIL=divergencias::text;
 END IF;
END $budget_phase_coherence$;

DO $post$
DECLARE b jsonb; a jsonb; live jsonb; x jsonb; y jsonb;
BEGIN
 SELECT catalogo INTO b FROM primeline_encarregado_20261004.snapshot;
 SELECT catalogo INTO a FROM primeline_encarregado_20261004.instalacao;
 live:=(SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',(SELECT array_agg(acl_item::text ORDER BY acl_item::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) acl_item),'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 IF a IS NULL OR live IS DISTINCT FROM a THEN RAISE EXCEPTION 'POSTCHECK_CATALOG_DRIFT'; END IF;
 -- Compara TODAS as tabelas, excetuando apenas as policies restritivas desta entrega.
 SELECT jsonb_agg(t||jsonb_build_object('policies',
  (SELECT jsonb_agg(p ORDER BY p->>'name') FROM jsonb_array_elements(nullif(t->'policies','null'::jsonb)) p
   WHERE p->>'name' NOT IN('encarregado_sem_select_direto','encarregado_sem_dml_direto','alertas_sessao_ativa','financeiro_empresa_insert','financeiro_empresa_update','financeiro_empresa_delete'))) ORDER BY t->>'name')
 INTO x FROM jsonb_array_elements(live->'tables') t;
 SELECT jsonb_agg(t ORDER BY t->>'name') INTO y FROM jsonb_array_elements(b->'tables') t;
 IF x IS DISTINCT FROM y THEN RAISE EXCEPTION 'LEGACY_TABLE_CATALOG_CHANGED'; END IF;
 SELECT jsonb_agg(f ORDER BY f->>'signature') INTO x FROM jsonb_array_elements(live->'functions') f
 WHERE f->>'signature' NOT IN('fn_encarregado_acesso_direto_bloqueado()','fn_subempreitadas_operacionais_obra(uuid)','fn_ausencias_equipa_encarregado(date,date)','fn_quadro_contexto_v1(date,date)','fn_equipa_obra_encarregado(date,uuid)','fn_quadro_ferias_encarregado_global(date,date)','fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()','fn_quadro_operar(text,jsonb,boolean,text)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid)','fn_custo_real_ligado(uuid,uuid,uuid)','fn_marcar_fatura_paga(uuid,date)','fn_desmarcar_fatura_paga(uuid)','fn_devolver_fatura_financeiro(uuid,text)','fn_avancar_estado_fluxo_fatura(uuid,text,date,text)','fn_marcar_faturacao_auto_paga(uuid,date,numeric)','fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)','fn_resolver_alerta(uuid)','fn_autorizacao_sessao_ativa()','fn_financeiro_autorizar_obra(uuid,boolean)','fn_financeiro_obra_da_empresa(uuid)','fn_decidir_fatura(uuid,text,text)','fn_decidir_faturacao_auto(uuid,text)','fn_devolver_fatura_administrativo(uuid,text)','fn_vincular_fatura_subempreitada(uuid,uuid)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)','fn_apagar_guia_fatura(uuid)','fn_apagar_anexo_fatura(uuid)','fn_eliminar_mapa_comparativo(uuid)','fn_eliminar_item_comparativo(uuid)','fn_concluir_custo_pl(uuid,numeric)','fn_concluir_custo_pl_fase(uuid,numeric)','fn_concluir_custos_pl_tarefa(uuid)','fn_confirmar_custo_real_pl(uuid,numeric)','fn_confirmar_remocao_custo_estimado_subempreitada(uuid)','fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)','fn_eliminar_proposta_comparativo(uuid)','fn_criar_fornecedor_comparativo(uuid,text)','fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)','fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)','fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)','fn_apagar_lancamento_gestao_obras(uuid)','fn_confirmar_compromisso_subempreitada(uuid)','fn_importar_orcamento_fases(uuid,jsonb,text)','fn_guardar_precos_candidato_subempreitada(uuid,jsonb)','fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])','fn_adjudicar_candidato_subempreitada(uuid,date,date,text)','fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)','fn_decidir_aditamento_subempreitada(uuid,text,text)','fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)','fn_importar_tees_xlsx(jsonb,text)','fn_importar_tees_revisoes(integer,uuid,jsonb,text)','fn_importar_subempreitadas_xlsx(jsonb,text)','fn_atualizar_venda_contrato_via_tee(uuid)','fn_definir_estado_mensal_v1(uuid,text,text,text,text)','fn_guardar_planeamento_lote(jsonb,text)','fn_economico_ator_atual()','fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)');
 SELECT jsonb_agg(f ORDER BY f->>'signature') INTO y FROM jsonb_array_elements(b->'functions') f
 WHERE f->>'signature' NOT IN('fn_quadro_contexto_v1(date,date)','fn_equipa_obra_encarregado(date,uuid)','fn_quadro_ferias_encarregado_global(date,date)','fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()','fn_quadro_operar(text,jsonb,boolean,text)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid)','fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid)','fn_custo_real_ligado(uuid,uuid,uuid)','fn_marcar_fatura_paga(uuid,date)','fn_desmarcar_fatura_paga(uuid)','fn_devolver_fatura_financeiro(uuid,text)','fn_avancar_estado_fluxo_fatura(uuid,text,date,text)','fn_marcar_faturacao_auto_paga(uuid,date,numeric)','fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)','fn_resolver_alerta(uuid)','fn_autorizacao_sessao_ativa()','fn_financeiro_autorizar_obra(uuid,boolean)','fn_financeiro_obra_da_empresa(uuid)','fn_decidir_fatura(uuid,text,text)','fn_decidir_faturacao_auto(uuid,text)','fn_devolver_fatura_administrativo(uuid,text)','fn_vincular_fatura_subempreitada(uuid,uuid)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)','fn_apagar_guia_fatura(uuid)','fn_apagar_anexo_fatura(uuid)','fn_eliminar_mapa_comparativo(uuid)','fn_eliminar_item_comparativo(uuid)','fn_concluir_custo_pl(uuid,numeric)','fn_concluir_custo_pl_fase(uuid,numeric)','fn_concluir_custos_pl_tarefa(uuid)','fn_confirmar_custo_real_pl(uuid,numeric)','fn_confirmar_remocao_custo_estimado_subempreitada(uuid)','fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)','fn_eliminar_proposta_comparativo(uuid)','fn_criar_fornecedor_comparativo(uuid,text)','fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)','fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)','fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)','fn_apagar_lancamento_gestao_obras(uuid)','fn_confirmar_compromisso_subempreitada(uuid)','fn_importar_orcamento_fases(uuid,jsonb,text)','fn_guardar_precos_candidato_subempreitada(uuid,jsonb)','fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])','fn_adjudicar_candidato_subempreitada(uuid,date,date,text)','fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)','fn_decidir_aditamento_subempreitada(uuid,text,text)','fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)','fn_importar_tees_xlsx(jsonb,text)','fn_importar_tees_revisoes(integer,uuid,jsonb,text)','fn_importar_subempreitadas_xlsx(jsonb,text)','fn_atualizar_venda_contrato_via_tee(uuid)','fn_definir_estado_mensal_v1(uuid,text,text,text,text)','fn_guardar_planeamento_lote(jsonb,text)','fn_economico_ator_atual()','fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)');
 IF x IS DISTINCT FROM y THEN RAISE EXCEPTION 'LEGACY_FUNCTION_CHANGED'; END IF;
 SELECT f INTO x FROM jsonb_array_elements(live->'functions') f WHERE f->>'signature'='fn_quadro_contexto_v1(date,date)';
 SELECT f||jsonb_build_object('definition',replace(f->>'definition',' OR u.funcao=''encarregado''','')) INTO y
 FROM jsonb_array_elements(b->'functions') f WHERE f->>'signature'='fn_quadro_contexto_v1(date,date)';
 IF x IS DISTINCT FROM y THEN RAISE EXCEPTION 'CONTEXT_PATCH_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(live->'functions') f
 JOIN jsonb_array_elements(b->'functions') old ON old->>'signature'=f->>'signature'
 WHERE f->>'signature' IN('fn_equipa_obra_encarregado(date,uuid)','fn_quadro_ferias_encarregado_global(date,date)')
 AND f IS DISTINCT FROM old||jsonb_build_object('acl','{postgres=X/postgres}'::text)) THEN RAISE EXCEPTION 'REVOKED_RPC_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid IN('public.fn_encarregado_acesso_direto_bloqueado()'::regprocedure,'public.fn_subempreitadas_operacionais_obra(uuid)'::regprocedure)
 AND (NOT p.prosecdef OR p.proowner<>'postgres'::regrole OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
 OR has_function_privilege('anon',p.oid,'EXECUTE') OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))) THEN RAISE EXCEPTION 'NEW_RPC_PRIVILEGES_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('public.fn_equipa_obra_encarregado(date,uuid)'::regprocedure,'public.fn_quadro_ferias_encarregado_global(date,date)'::regprocedure) AND (has_function_privilege('authenticated',oid,'EXECUTE') OR has_function_privilege('anon',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'GLOBAL_RPC_STILL_EXPOSED'; END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid IN('public.colaboradores'::regclass,'public.subempreitadas'::regclass) AND polname='encarregado_sem_select_direto' AND NOT polpermissive AND polcmd='r')<>2 THEN RAISE EXCEPTION 'RESTRICTIVE_GUARD_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('fn_ajustar_saida_prevista_mensal(uuid,date,numeric)'::regprocedure,'fn_atualizar_melhor_preco_comparativo(uuid)'::regprocedure,'fn_congelar_planeamento_baseline(uuid)'::regprocedure,'fn_verificar_congelamentos_pendentes()'::regprocedure)
 AND (has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('authenticated',oid,'EXECUTE') OR NOT has_function_privilege('service_role',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'INTERNAL_WRITER_EXPOSED'; END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polname='encarregado_sem_select_direto' AND NOT polpermissive AND polcmd='r')<>7 THEN RAISE EXCEPTION 'CONSOLIDATED_READ_GUARDS_MISSING'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='quadro_pessoal_alocacao'::regclass AND polname='encarregado_sem_dml_direto' AND NOT polpermissive AND polcmd='*') THEN RAISE EXCEPTION 'LEGACY_DML_GUARD_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(live->'functions') f JOIN jsonb_array_elements(b->'functions') old ON old->>'signature'=f->>'signature'
 WHERE f->>'signature' IN('fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()')
 AND f-'acl' IS DISTINCT FROM old-'acl') THEN RAISE EXCEPTION 'INTERNAL_WRITER_BODY_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_ausencias_equipa_encarregado(date,date)'::regprocedure
 AND (NOT p.prosecdef OR p.proowner<>'postgres'::regrole OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('anon',p.oid,'EXECUTE') OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))) THEN RAISE EXCEPTION 'ABSENCE_RPC_INVALID'; END IF;
 RAISE NOTICE 'POSTCHECK_ENCARREGADO_OK';
END $post$;
-- Exercita as identidades reais apenas em SELECT, sem emitir dados/PII.
-- As claims e o papel são locais à transação; o ROLLBACK repõe a sessão.
DO $roles$
DECLARE r record; n bigint; blocked boolean; works uuid[]; work uuid; tab text;
BEGIN
 FOR r IN SELECT id,auth_user_id,funcao,empresa_id FROM public.utilizadores
 WHERE ativo IS TRUE AND auth_user_id IS NOT NULL LOOP
  SELECT array_agg(o.id) INTO works FROM public.obras o
   JOIN public.obra_responsaveis b ON b.obra_id=o.id
   WHERE b.utilizador_id=r.id AND b.papel='encarregado' AND o.empresa_id=r.empresa_id;
  PERFORM set_config('request.jwt.claim.sub',r.auth_user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',r.auth_user_id,'role','authenticated')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT public.fn_encarregado_acesso_direto_bloqueado() INTO blocked;
  IF blocked IS DISTINCT FROM (r.funcao='encarregado') THEN RAISE EXCEPTION 'ROLE_GUARD_MISMATCH'; END IF;
  IF r.funcao='encarregado' THEN
   SELECT count(*) INTO n FROM public.colaboradores;
   IF n<>0 THEN RAISE EXCEPTION 'COLLABORATORS_EXPOSED'; END IF;
   SELECT count(*) INTO n FROM public.subempreitadas;
   IF n<>0 THEN RAISE EXCEPTION 'SUBCONTRACTS_EXPOSED'; END IF;
   FOREACH tab IN ARRAY ARRAY['ausencias','quadro_pessoal_alocacao','fornecedores','fornecedores_aliases','fornecedores_mesclagens','avaliacoes_subempreiteiro','faturas','pagamentos_subempreitada'] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I',tab) INTO n;
    IF n<>0 THEN RAISE EXCEPTION 'DIRECT_SCOPE_EXPOSED: %',tab; END IF;
   END LOOP;
   FOREACH work IN ARRAY coalesce(works,'{}'::uuid[]) LOOP
    SELECT count(*) INTO n FROM public.fn_subempreitadas_operacionais_obra(work) s WHERE s.obra_id<>work;
    IF n<>0 THEN RAISE EXCEPTION 'OPERATIONAL_SCOPE_INVALID'; END IF;
   END LOOP;
  END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
 RAISE NOTICE 'POSTCHECK_ROLES_OK';
END $roles$;

DO $financial$
DECLARE sig text; definition text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.alertas'::regclass
  AND polname='alertas_sessao_ativa' AND NOT polpermissive AND polcmd='r'
  AND pg_get_expr(polqual,polrelid)='fn_autorizacao_sessao_ativa()') THEN
  RAISE EXCEPTION 'ALERT_ACTIVE_GUARD_MISSING';
 END IF;
 FOREACH sig IN ARRAY ARRAY['fn_marcar_fatura_paga(uuid,date)','fn_desmarcar_fatura_paga(uuid)','fn_devolver_fatura_financeiro(uuid,text)','fn_avancar_estado_fluxo_fatura(uuid,text,date,text)','fn_marcar_faturacao_auto_paga(uuid,date,numeric)','fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)','fn_resolver_alerta(uuid)','fn_decidir_fatura(uuid,text,text)','fn_decidir_faturacao_auto(uuid,text)','fn_devolver_fatura_administrativo(uuid,text)','fn_vincular_fatura_subempreitada(uuid,uuid)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,jsonb)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)','fn_apagar_guia_fatura(uuid)','fn_apagar_anexo_fatura(uuid)','fn_eliminar_mapa_comparativo(uuid)','fn_eliminar_item_comparativo(uuid)'] LOOP
  SELECT pg_get_functiondef(sig::regprocedure) INTO definition;
  IF position('fn_autorizacao_sessao_ativa()' in definition)=0
   OR (sig NOT IN('fn_resolver_alerta(uuid)','fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)') AND position('fn_financeiro_autorizar_obra' in definition)=0)
   OR has_function_privilege('anon',sig,'EXECUTE')
   OR NOT has_function_privilege('authenticated',sig,'EXECUTE')
   OR has_function_privilege('service_role',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'FINANCIAL_RPC_GUARD_INVALID: %',sig;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_proc WHERE oid=sig::regprocedure
   AND (NOT prosecdef OR proowner<>'postgres'::regrole OR proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp'])) THEN
   RAISE EXCEPTION 'FINANCIAL_RPC_OWNER_PATH_INVALID';
  END IF;
 END LOOP;
 IF has_function_privilege('authenticated','public.fn_financeiro_autorizar_obra(uuid,boolean)','EXECUTE')
 OR has_function_privilege('anon','public.fn_financeiro_autorizar_obra(uuid,boolean)','EXECUTE') THEN
  RAISE EXCEPTION 'PRIVATE_AUTH_HELPER_EXPOSED';
 END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid IN('public.faturas'::regclass,'public.faturacao'::regclass,'public.faturas_itens'::regclass,'public.faturas_anexos'::regclass,'public.faturas_guias'::regclass,'public.mapas_comparativos'::regclass,'public.comparativo_itens'::regclass,'public.comparativo_propostas'::regclass,'public.comparativo_ajustes'::regclass,'public.comparativo_itens_precos'::regclass) AND polname IN('financeiro_empresa_insert','financeiro_empresa_update','financeiro_empresa_delete') AND NOT polpermissive)<>24 THEN RAISE EXCEPTION 'FINANCIAL_DML_GUARDS_MISSING'; END IF;
 RAISE NOTICE 'POSTCHECK_FINANCIAL_STRUCTURAL_OK';
END $financial$;

-- Apenas SELECT: exercita as guardas puras com as identidades existentes.
-- As RPCs de escrita NÃO são invocadas no postcheck real; provas de escrita/atomicidade são locais.
DO $financial_scope$
DECLARE u record; o record; expected boolean; actual boolean; n bigint;
BEGIN
 FOR u IN SELECT auth_user_id,empresa_id,ativo FROM public.utilizadores WHERE auth_user_id IS NOT NULL LOOP
  PERFORM set_config('request.jwt.claim.sub',u.auth_user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.auth_user_id,'role','authenticated')::text,true);
  IF public.fn_autorizacao_sessao_ativa() IS DISTINCT FROM (u.ativo IS TRUE) THEN RAISE EXCEPTION 'ACTIVE_SESSION_GUARD_INVALID'; END IF;
  FOR o IN SELECT id,empresa_id FROM public.obras LOOP
   expected:=u.ativo IS TRUE AND o.empresa_id IS NOT NULL AND o.empresa_id IS NOT DISTINCT FROM u.empresa_id;
   SELECT public.fn_financeiro_obra_da_empresa(o.id) INTO actual;
   IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FINANCIAL_COMPANY_GUARD_INVALID'; END IF;
  END LOOP;
  IF u.ativo IS NOT TRUE THEN
   EXECUTE 'SET LOCAL ROLE authenticated';
   SELECT count(*) INTO n FROM public.alertas;
   IF n<>0 THEN RAISE EXCEPTION 'INACTIVE_ALERTS_EXPOSED'; END IF;
   EXECUTE 'RESET ROLE';
  END IF;
 END LOOP;
 RAISE NOTICE 'POSTCHECK_FINANCIAL_SCOPE_READONLY_OK';
END $financial_scope$;

-- Comparação exata dos corpos aprovados, além de owner, path, SECURITY DEFINER e ACL.
DO $economic_writers$
DECLARE r record; p record; original_definition text;
BEGIN
 FOR r IN SELECT * FROM (VALUES ('fn_concluir_custo_pl(uuid,numeric)','708583b03504ec5a6b1bfb0739b1f075'),
('fn_concluir_custo_pl_fase(uuid,numeric)','9acb569e79dd572affcb7887b3a1b8b7'),
('fn_concluir_custos_pl_tarefa(uuid)','28c517c80cb55eedd67769a2fc1aa523'),
('fn_confirmar_custo_real_pl(uuid,numeric)','058f66f459c2c3240cf753ea733131c0'),
('fn_confirmar_remocao_custo_estimado_subempreitada(uuid)','161c23258fd524c7577b1cbca33fff42'),
('fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)','04263a43f78255218291a967f5d585ef'),
('fn_eliminar_proposta_comparativo(uuid)','3783e785e69c1e19fdc3d0bb36e71b92'),
('fn_criar_fornecedor_comparativo(uuid,text)','faf332ee600aec1530434e06d6d625c1'),
('fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)','a020a6a93e562a5f7b0870bda7905f8b'),
('fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)','ce70a57ee104dd247587ab9f64d45bc5'),
('fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)','6ac734f9c9f630ee7e6128cfec97042b'),
('fn_apagar_lancamento_gestao_obras(uuid)','5fee8038113c700a6d42d71b4ed07a4c')) expected(signature,body_hash) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=r.signature::regprocedure;
  SELECT f->>'definition' INTO original_definition FROM primeline_encarregado_20261004.snapshot b
  CROSS JOIN LATERAL jsonb_array_elements(b.catalogo->'functions') f WHERE f->>'signature'=r.signature;
  IF md5(replace(p.prosrc,chr(13),''))<>r.body_hash OR NOT p.prosecdef
   OR original_definition IS NULL
   OR split_part(pg_get_functiondef(p.oid),' LANGUAGE ',1) IS DISTINCT FROM split_part(original_definition,' LANGUAGE ',1)
   OR p.proowner<>'postgres'::regrole
   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp']
   OR position('fn_financeiro_autorizar_obra' in p.prosrc)=0
   OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x)
      IS DISTINCT FROM '{authenticated=X/postgres,postgres=X/postgres}'
  THEN RAISE EXCEPTION 'ECONOMIC_WRITER_DEFINITION_ACL_INVALID: %',r.signature; END IF;
 END LOOP;
 SELECT * INTO p FROM pg_proc WHERE oid='public.fn_financeiro_autorizar_obra(uuid,boolean)'::regprocedure;
 IF NOT p.prosecdef OR p.proowner<>'postgres'::regrole OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x)
     IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'PRIVATE_TENANT_HELPER_INVALID'; END IF;
 RAISE NOTICE 'POSTCHECK_ECONOMIC_WRITERS_OK';
END $economic_writers$;
DO $economic_final_writers$
DECLARE r record; p record; old text; expected_acl text;
BEGIN
 FOR r IN SELECT * FROM (VALUES ('fn_confirmar_compromisso_subempreitada(uuid)','db5da79a79d06ea83a8e509623aee593',true),
('fn_importar_orcamento_fases(uuid,jsonb,text)','429978a320a0c174b517757382a5b63f',true),
('fn_guardar_precos_candidato_subempreitada(uuid,jsonb)','d03801deb8424efabae54806210bd4a8',true),
('fn_criar_consulta_subempreitada(uuid,uuid,text,uuid[])','f9992648dee1f0116e436cb187bc9d67',true),
('fn_adjudicar_candidato_subempreitada(uuid,date,date,text)','55724f5de22a5386fc5361144ecb4057',true),
('fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid)','49da82ff134761154e4aac35015a9846',true),
('fn_decidir_aditamento_subempreitada(uuid,text,text)','ee10d59c9dbf6746fb1e9fdeccf77283',true),
('fn_concluir_subempreitada_com_avaliacao(uuid,integer,integer,integer,integer,text)','baa3dc5052160f6e58de8dc7fd11ffba',true),
('fn_importar_tees_xlsx(jsonb,text)','292ae2eeb93f4f92437ab6e227ab17c6',true),
('fn_importar_tees_revisoes(integer,uuid,jsonb,text)','4b58638c1fbfdcbaab7d363835af1944',true),
('fn_importar_subempreitadas_xlsx(jsonb,text)','8ddaf535efb60d08b75877c776a84c6d',true),
('fn_atualizar_venda_contrato_via_tee(uuid)','7049cc347b24caa290f75fe499ee02fa',false),
('fn_definir_estado_mensal_v1(uuid,text,text,text,text)','f3720ff97b9c0a43797a0a3a362c867f',true),
('fn_guardar_planeamento_lote(jsonb,text)','6243fac0125b395cb059ac500ab89113',true),
('fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','41ec6ed9fa4ab8507253f2ae9f3fa7d4',true),
('fn_criar_obra_de_modelo(uuid,text,text,text,text,text,text,uuid,text,date,date,boolean)','0cd5012e2aae31634e9c8c8b773590c6',true)) expected(signature,body_hash,external) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=r.signature::regprocedure;
  SELECT f->>'definition' INTO old FROM primeline_encarregado_20261004.snapshot b
  CROSS JOIN LATERAL jsonb_array_elements(b.catalogo->'functions') f WHERE f->>'signature'=r.signature;
  expected_acl:=CASE WHEN r.external THEN '{authenticated=X/postgres,postgres=X/postgres}' ELSE '{postgres=X/postgres}' END;
  IF md5(replace(p.prosrc,chr(13),''))<>r.body_hash OR NOT p.prosecdef OR p.proowner<>'postgres'::regrole
   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp']
   OR old IS NULL OR split_part(pg_get_functiondef(p.oid),' LANGUAGE ',1) IS DISTINCT FROM split_part(old,' LANGUAGE ',1)
   OR position('fn_financeiro_autorizar_obra' in p.prosrc)=0
   OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x) IS DISTINCT FROM expected_acl
  THEN RAISE EXCEPTION 'ECONOMIC_FINAL_WRITER_INVALID: %',r.signature; END IF;
 END LOOP;
 SELECT * INTO p FROM pg_proc WHERE oid='public.fn_economico_ator_atual()'::regprocedure;
 IF NOT p.prosecdef OR p.proowner<>'postgres'::regrole OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']
  OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x) IS DISTINCT FROM '{postgres=X/postgres}'
 THEN RAISE EXCEPTION 'ECONOMIC_ACTOR_HELPER_EXPOSED'; END IF;
 RAISE NOTICE 'POSTCHECK_ECONOMIC_FINAL_OK';
END $economic_final_writers$;
ROLLBACK;

BEGIN READ ONLY;
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'a' THEN RAISE EXCEPTION 'PHASE_A_REQUIRED'; END IF;
 IF to_regclass('public.folha_registos') IS NOT NULL OR to_regnamespace('folha_privado') IS NOT NULL THEN RAISE EXCEPTION 'FOLHA_V2_ALREADY_INSTALLED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.quadro_pessoal_alocacao'::regclass AND polname='encarregado_sem_dml_direto' AND NOT polpermissive) THEN RAISE EXCEPTION 'HOTFIX_POLICY_REQUIRED'; END IF;
END $$;
-- Explicit legacy projection: fail closed if required source columns are absent.
DO $legacy_projection$
DECLARE missing text[];
BEGIN
 SELECT array_agg(required ORDER BY required) INTO missing
 FROM unnest(ARRAY['id','empresa_id','obra_id','colaborador_id','data','horas','entrada_manha','saida_manha','entrada_tarde','saida_tarde','periodos_alocados','estado','registado_por','atualizado_por','criado_em','atualizado_em']) required
 WHERE NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.ponto_pessoal_obra'::regclass AND attname=required AND attnum>0 AND NOT attisdropped);
 IF missing IS NOT NULL THEN RAISE EXCEPTION 'LEGACY_PROJECTION_COLUMNS_MISSING: %',missing; END IF;
END $legacy_projection$;
SELECT 'FOLHA_V2_PRECHECK_OK' status;
COMMIT;