-- Postcheck B: somente leitura, aborta em divergência.
DO $$ DECLARE r record; role_name text; f record; t text; priv text; BEGIN
 FOR t IN SELECT unnest(ARRAY['quadro_dias_revisoes','quadro_operacoes','quadro_escrita_interna']) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=to_regclass('public.'||t) AND c.relrowsecurity AND pg_get_userbyid(c.relowner)='postgres') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: tabela privada/RLS/owner %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: policy em tabela privada %',t; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(role_name,'public.'||t,priv) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: acesso privado %, %, %',role_name,t,priv; END IF;
   END LOOP;
   FOR r IN SELECT attname FROM pg_attribute WHERE attrelid=to_regclass('public.'||t) AND attnum>0 AND NOT attisdropped LOOP
    IF has_column_privilege(role_name,'public.'||t,r.attname,'SELECT') OR has_column_privilege(role_name,'public.'||t,r.attname,'INSERT') OR has_column_privilege(role_name,'public.'||t,r.attname,'UPDATE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: grant de coluna privada %',t; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 FOR f IN SELECT p.*,p.oid::regprocedure::text signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND (p.proname LIKE 'fn_quadro_%v1' OR p.proname IN('fn_quadro_aplicar_interno','fn_quadro_renomear_interno','fn_quadro_resolver_data','fn_quadro_dia_explicito','fn_quadro_ler_obra','fn_quadro_criar_colaborador_interno')) LOOP
  IF NOT f.prosecdef OR pg_get_userbyid(f.proowner)<>'postgres' OR NOT coalesce(f.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp'] THEN RAISE EXCEPTION 'POSTCHECK_FAILED: owner/security/search_path %',f.signature; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(role_name,f.oid,'EXECUTE') IS DISTINCT FROM (role_name='authenticated' AND (f.proname IN('fn_quadro_operar_v1','fn_quadro_contexto_v1') OR f.proname='fn_quadro_ler_obra')) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: EXECUTE %, %',role_name,f.signature; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: PUBLIC execute %',f.signature; END IF;
 END LOOP;
 FOR f IN SELECT * FROM primeline_backup.quadro_funcoes_20261001 WHERE assinatura LIKE 'fn_criar_colaborador_com_alocacao(%' OR assinatura LIKE 'fn_rh_guardar_interno(%' OR assinatura='fn_registar_movimento_quadro()' OR assinatura='fn_quadro_proteger_escrita()' OR assinatura='fn_quadro_notificar_movimentacao_encarregado()'  LOOP
  IF (SELECT p.proacl::text FROM pg_proc p WHERE p.oid=f.assinatura::regprocedure) IS DISTINCT FROM f.acl OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid=f.assinatura::regprocedure) IS DISTINCT FROM f.owner THEN RAISE EXCEPTION 'POSTCHECK_FAILED: ACL/owner legado modificado %',f.assinatura; END IF;
 END LOOP;
 FOR f IN SELECT * FROM primeline_backup.quadro_funcoes_20261001 WHERE assinatura LIKE 'fn_listar_ponto_obra(%' OR assinatura LIKE 'fn_guardar_ponto_obra(%' OR assinatura LIKE 'fn_pode_gerir_quadro(%' OR assinatura LIKE 'fn_quadro_minha_obra(%' OR assinatura='fn_pode_consultar_quadro()' LOOP
  IF replace(pg_get_functiondef(f.assinatura::regprocedure),chr(13),'') IS DISTINCT FROM replace(f.definicao,chr(13),'') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: consumidor legado alterado %',f.assinatura; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT tgisinternal AND tgenabled<>'O') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: trigger desativado'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p') AND p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?quadro_pessoal_alocacao\M' AND p.proname NOT IN('fn_quadro_aplicar_interno')) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: writer não inventariado'; END IF;
 PERFORM set_config('search_path','public,pg_temp',true);
 IF (SELECT md5(qual) FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_alocacao' AND policyname='quadro_controlado_leitura') IS DISTINCT FROM 'a28315d5f9aada494df26ae0bf357c4f'
 OR (SELECT md5(qual) FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_movimentos' AND policyname='quadro_controlado_historico') IS DISTINCT FROM '4d3f4ba0d23b763cccd6edbf534e354e' THEN RAISE EXCEPTION 'POSTCHECK_FAILED: expressão das policies finais divergente (referência PostgreSQL 17.6)'; END IF;
 FOREACH t IN ARRAY ARRAY['quadro_pessoal_alocacao','quadro_pessoal_movimentos'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||t) AND relrowsecurity) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: RLS final %',t; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(role_name,'public.'||t,priv) IS DISTINCT FROM (role_name='authenticated' AND priv='SELECT') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: ACL final %, %, %',role_name,t,priv; END IF;
   END LOOP;
   FOR r IN SELECT attname FROM pg_attribute WHERE attrelid=to_regclass('public.'||t) AND attnum>0 AND NOT attisdropped LOOP
    IF has_column_privilege(role_name,'public.'||t,r.attname,'INSERT') OR has_column_privilege(role_name,'public.'||t,r.attname,'UPDATE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: DML de coluna final %',t; END IF;
   END LOOP;
  END LOOP;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename=t AND cmd='SELECT' AND roles=ARRAY['authenticated']::name[])<>1 OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t AND cmd<>'SELECT') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: policies finais %',t; END IF;
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF has_function_privilege(role_name,'public.fn_quadro_operar(text,jsonb,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: RPC antiga ainda exposta'; END IF;
 END LOOP;
 FOR r IN SELECT c.oid FROM pg_class c JOIN pg_depend d ON d.objid=c.oid WHERE c.relkind='S' AND d.refobjid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass) LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_sequence_privilege(role_name,r.oid,'USAGE') OR has_sequence_privilege(role_name,r.oid,'UPDATE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: grant de sequência'; END IF;
  END LOOP;
 END LOOP;
END $$;
-- UUIDs usam gen_random_uuid(): não são introduzidas sequências novas.

-- Controlo de rollout não é RPC pública; owner/ACL/RLS privados obrigatórios.
SELECT primeline_quadro_rollout.exigir_privacidade();
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM primeline_quadro_rollout.controlo c JOIN primeline_quadro_rollout.validacoes v ON v.instalacao_id=c.instalacao_id AND v.tentativa=c.tentativa WHERE c.singleton AND c.estado='b' AND c.fase_b_aplicada_em IS NOT NULL AND c.contract_version=1 AND c.frontend_release_id='quadro_frontend_contract_v1' AND v.contract_version=c.contract_version AND v.frontend_release_id=c.frontend_release_id AND v.consumida_em IS NOT NULL AND v.invalidada_em IS NULL AND v.identidade_a=c.identidade_a) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: autorização privada de rollout incoerente'; END IF;
END $$;

-- Recompute the CURRENT catalog; compare to validated A plus the exact allowed B changes.
DO $postcheck_b$ DECLARE v_expected jsonb; v_current jsonb; v_nodes jsonb; v_record text; v_trigger jsonb; v_required record;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 PERFORM set_config('search_path','public,pg_temp',true);
 IF to_regclass('primeline_backup.quadro_fase_b_estrutura_20261001') IS NULL THEN RAISE EXCEPTION 'POSTCHECK_FAILED: referência estrutural A ausente'; END IF;
 IF (SELECT count(*) FROM primeline_backup.quadro_fase_b_estrutura_20261001)<>1 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: referência estrutural ambígua'; END IF;
 -- These seven triggers are mandatory even if a deficient A was captured.
 FOR v_required IN SELECT * FROM (VALUES
 ('trg_00_quadro_proteger_escrita','CREATE TRIGGER trg_00_quadro_proteger_escrita BEFORE INSERT OR DELETE OR UPDATE ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_quadro_proteger_escrita()'),
 ('trg_auditoria_quadro_pessoal_alocacao','CREATE TRIGGER trg_auditoria_quadro_pessoal_alocacao AFTER INSERT OR DELETE OR UPDATE ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_registar_log_auditoria(''id'')'),
 ('trg_bloquear_quadro_pessoal_ausencia','CREATE TRIGGER trg_bloquear_quadro_pessoal_ausencia BEFORE INSERT OR UPDATE OF colaborador_id, data ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_bloquear_registo_em_ausencia()'),
 ('trg_quadro_notificar_movimentacao_encarregado','CREATE TRIGGER trg_quadro_notificar_movimentacao_encarregado AFTER INSERT OR UPDATE OF obra_id ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_quadro_notificar_movimentacao_encarregado()'),
 ('trg_quadro_pessoal_movimentos','CREATE TRIGGER trg_quadro_pessoal_movimentos AFTER INSERT OR DELETE OR UPDATE ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_registar_movimento_quadro()'),
 ('trg_validar_conflito_quadro_pessoal','CREATE TRIGGER trg_validar_conflito_quadro_pessoal BEFORE INSERT OR UPDATE OF colaborador_id, data, periodo, obra_id, tipo_alocacao, descricao_livre ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_validar_conflito_quadro_pessoal()'),
 ('trg_00_quadro_lock_escrita_v1','CREATE TRIGGER trg_00_quadro_lock_escrita_v1 BEFORE INSERT OR DELETE OR UPDATE ON public.quadro_pessoal_alocacao FOR EACH STATEMENT EXECUTE FUNCTION fn_quadro_lock_escrita_v1()')
 ) required(name,definition) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT t.tgisinternal AND t.tgname=v_required.name AND t.tgenabled='O' AND pg_get_triggerdef(t.oid)=v_required.definition) THEN
   RAISE EXCEPTION 'POSTCHECK_FAILED: trigger obrigatório ausente/divergente %',v_required.name;
  END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace n WHERE n.nspname='primeline_backup' AND pg_get_userbyid(n.nspowner)='postgres') OR
 EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_backup' AND a.grantee<>n.nspowner) OR
 EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid=to_regclass('primeline_backup.quadro_fase_b_estrutura_20261001') AND (pg_get_userbyid(c.relowner)<>'postgres' OR a.grantee<>c.relowner)) THEN
  RAISE EXCEPTION 'POSTCHECK_FAILED: referência estrutural deve permanecer privada/owner postgres';
 END IF;
 SELECT b.estrutura INTO STRICT v_expected FROM primeline_backup.quadro_fase_b_estrutura_20261001 b;
 -- B changes exactly two function bodies, two function ACLs, two table ACLs and two policies.
 SELECT jsonb_agg(CASE
  WHEN x->>'signature'='public.fn_quadro_proteger_escrita()' THEN jsonb_set(x,'{definition}','"f7fbf510c09f43ce052e4500d02d067b"')
  WHEN x->>'signature'='public.fn_quadro_operar(text, jsonb, boolean, text)' THEN jsonb_set(jsonb_set(x,'{definition}','"182ccfb29a42f69b7b2523d0a704610b"'),'{acl}',(SELECT jsonb_agg(a ORDER BY a->>'grantee',a->>'privilege') FROM jsonb_array_elements(x->'acl') a WHERE a->>'grantee' NOT IN('PUBLIC','anon','authenticated','service_role')))
  WHEN x->>'signature'='public.fn_quadro_ler_obra(uuid)' THEN jsonb_set(x,'{acl}',(SELECT jsonb_agg(a ORDER BY a->>'grantee',a->>'privilege') FROM (SELECT a FROM jsonb_array_elements(x->'acl') a WHERE a->>'grantee'<>'authenticated' UNION ALL SELECT '{"grantee":"authenticated","grantor":"postgres","privilege":"EXECUTE","grantable":false}'::jsonb) entries))
  ELSE x END ORDER BY x->>'signature') INTO v_nodes FROM jsonb_array_elements(v_expected->'functions') x;
 v_expected:=jsonb_set(v_expected,'{functions}',v_nodes);
 SELECT jsonb_agg(CASE WHEN x->>'table' IN('public.quadro_pessoal_alocacao','public.quadro_pessoal_movimentos') THEN
   jsonb_set(x,'{acl}',(SELECT jsonb_agg(a ORDER BY a->>'grantee',a->>'privilege') FROM (SELECT a FROM jsonb_array_elements(x->'acl') a WHERE a->>'grantee' NOT IN('PUBLIC','anon','authenticated','service_role') UNION ALL SELECT '{"grantee":"authenticated","grantor":"postgres","privilege":"SELECT","grantable":false}'::jsonb) entries)) ELSE x END ORDER BY x->>'table')
 INTO v_nodes FROM jsonb_array_elements(v_expected->'tables') x;
 v_expected:=jsonb_set(v_expected,'{tables}',v_nodes);
 SELECT jsonb_agg(CASE WHEN x->>'table' IN('public.quadro_pessoal_alocacao','public.quadro_pessoal_movimentos') THEN jsonb_set(x,'{acl}','null') ELSE x END ORDER BY ordinal)
 INTO v_nodes FROM jsonb_array_elements(v_expected->'columns') WITH ORDINALITY entries(x,ordinal);
 v_expected:=jsonb_set(v_expected,'{columns}',v_nodes);
 v_expected:=jsonb_set(v_expected,'{policies}',coalesce((SELECT jsonb_agg(x ORDER BY x->>'schema',x->>'table',x->>'name') FROM (
  SELECT x FROM jsonb_array_elements(v_expected->'policies') x WHERE NOT(x->>'schema'='public' AND x->>'table' IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos'))
  UNION ALL SELECT '{"schema":"public","table":"quadro_pessoal_alocacao","name":"quadro_controlado_leitura","permissive":"PERMISSIVE","cmd":"SELECT","roles":["authenticated"],"qual":"a28315d5f9aada494df26ae0bf357c4f","check":null}'::jsonb
  UNION ALL SELECT '{"schema":"public","table":"quadro_pessoal_movimentos","name":"quadro_controlado_historico","permissive":"PERMISSIVE","cmd":"SELECT","roles":["authenticated"],"qual":"4d3f4ba0d23b763cccd6edbf534e354e","check":null}'::jsonb
 ) entries),'[]'::jsonb));
 SELECT jsonb_build_object(
 'functions',coalesce((SELECT jsonb_agg(jsonb_build_object('signature',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
   'definition',md5(replace(pg_get_functiondef(p.oid),chr(13),'')),'owner',pg_get_userbyid(p.proowner),'sd',p.prosecdef,'config',p.proconfig,
   'acl',(SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,'grantor',pg_get_userbyid(x.grantor),'privilege',x.privilege_type,'grantable',x.is_grantable) ORDER BY CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,x.privilege_type) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x)) ORDER BY n.nspname,p.proname,oidvectortypes(p.proargtypes))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.prokind IN('f','p') AND
  ((n.nspname='public' AND (p.proname LIKE 'fn_quadro_%' OR p.proname LIKE 'fn_rh_%' OR p.proname IN('fn_criar_colaborador_com_alocacao','fn_registar_movimento_quadro','fn_pode_gerir_quadro','fn_pode_consultar_quadro','fn_listar_ponto_obra','fn_guardar_ponto_obra') OR p.prosrc ILIKE '%quadro_pessoal_alocacao%' OR p.prosrc ~* '(^|[^a-z_])execute([^a-z_]|$)' OR 'regclass'::regtype=ANY(p.proargtypes::oid[]) OR p.oid IN(SELECT tgfoid FROM pg_trigger WHERE tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT tgisinternal))) OR n.nspname='primeline_quadro_rollout')),'[]'::jsonb),
 'tables',coalesce((SELECT jsonb_agg(jsonb_build_object('table',format('%I.%I',n.nspname,c.relname),'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
   'acl',(SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,'grantor',pg_get_userbyid(x.grantor),'privilege',x.privilege_type,'grantable',x.is_grantable) ORDER BY CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,x.privilege_type) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x)) ORDER BY n.nspname,c.relname)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.oid=ANY(ARRAY['public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_pessoal_rpc_permit'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass])),'[]'::jsonb),
 'columns',coalesce((SELECT jsonb_agg(jsonb_build_object('table',format('%I.%I',n.nspname,c.relname),'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),
   'acl',(SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,'grantor',pg_get_userbyid(x.grantor),'privilege',x.privilege_type,'grantable',x.is_grantable) ORDER BY CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,x.privilege_type) FROM aclexplode(a.attacl) x)) ORDER BY n.nspname,c.relname,a.attnum)
  FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attrelid=ANY(ARRAY['public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_pessoal_rpc_permit'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass]) AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
 'triggers',coalesce((SELECT jsonb_agg(jsonb_build_object('table',format('%I.%I',n.nspname,c.relname),'name',t.tgname,'enabled',t.tgenabled,'type',t.tgtype,'function',t.tgfoid::regprocedure::text,'definition',pg_get_triggerdef(t.oid)) ORDER BY n.nspname,c.relname,t.tgname)
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE t.tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT t.tgisinternal),'[]'::jsonb),
 'constraints',coalesce((SELECT jsonb_agg(jsonb_build_object('table',format('%I.%I',n.nspname,c.relname),'name',x.conname,'definition',pg_get_constraintdef(x.oid),'validated',x.convalidated) ORDER BY n.nspname,c.relname,x.conname)
  FROM pg_constraint x JOIN pg_class c ON c.oid=x.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE x.conrelid=ANY(ARRAY['public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_pessoal_rpc_permit'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass])),'[]'::jsonb),
 'indexes',coalesce((SELECT jsonb_agg(jsonb_build_object('name',format('%I.%I',n.nspname,c.relname),'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'ready',i.indisready) ORDER BY n.nspname,c.relname)
  FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE i.indrelid=ANY(ARRAY['public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_pessoal_rpc_permit'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass]) OR c.relname='alertas_ocorrencia_unica_idx'),'[]'::jsonb),
 'policies',coalesce((SELECT jsonb_agg(jsonb_build_object('schema',p.schemaname,'table',p.tablename,'name',p.policyname,'permissive',p.permissive,'cmd',p.cmd,'roles',p.roles,'qual',md5(p.qual),'check',md5(p.with_check)) ORDER BY p.schemaname,p.tablename,p.policyname)
  FROM pg_policies p WHERE (p.schemaname='public' AND p.tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos','quadro_pessoal_rpc_permit','quadro_dias_revisoes','quadro_operacoes','quadro_escrita_interna')) OR p.schemaname='primeline_quadro_rollout'),'[]'::jsonb),
 'schema', (SELECT jsonb_build_object('name',n.nspname,'owner',pg_get_userbyid(n.nspowner),'acl',(SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,'grantor',pg_get_userbyid(x.grantor),'privilege',x.privilege_type,'grantable',x.is_grantable) ORDER BY CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee)::text END,x.privilege_type) FROM aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x)) FROM pg_namespace n WHERE n.nspname='primeline_quadro_rollout')
) INTO v_current;
 -- Exact set equality detects a missing, extra, disabled, rebound or altered trigger.
 FOR v_trigger IN SELECT value FROM jsonb_array_elements(v_expected->'triggers') LOOP
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_current->'triggers') actual WHERE actual=v_trigger) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: trigger divergente %.%',v_trigger->>'table',v_trigger->>'name'; END IF;
 END LOOP;
 -- Compare every definition/ACL/policy/object, not a previously recorded identity alone.
 IF v_current IS DISTINCT FROM v_expected THEN
  SELECT string_agg(k,', ' ORDER BY k) INTO v_record FROM jsonb_object_keys(v_expected) k WHERE v_current->k IS DISTINCT FROM v_expected->k;
  RAISE EXCEPTION 'POSTCHECK_FAILED: identidade estrutural B divergente (%)',v_record;
 END IF;
 RAISE NOTICE 'POSTCHECK_B_IDENTIDADE_ATUAL: %',md5(v_current::text);
END $postcheck_b$;

SELECT 'POSTCHECK_B_OK' status;
