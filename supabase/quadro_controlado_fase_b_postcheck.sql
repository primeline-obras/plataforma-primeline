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
SELECT 'POSTCHECK_B_OK' status;
