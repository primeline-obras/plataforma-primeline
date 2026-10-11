-- Manual authorization only. Restore catalog, NEVER restore/erase operational facts.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos,public.quadro_equipa_permanencias,public.quadro_dias_revisoes,public.quadro_operacoes,public.quadro_escrita_interna,public.folha_registos,public.folha_historico,public.folha_externos,public.folha_externos_dias,public.folha_externos_permanencias,public.folha_horarios,public.folha_config_empresa,public.folha_he,public.folha_vencimentos,public.folha_tarefas_reportes,public.folha_gestao_historico,public.ponto_pessoal_obra,public.colaboradores,public.utilizadores,public.obras,public.ausencias,folha_privado.operacoes,folha_privado.equipa_revisoes,folha_privado.periodos_revisoes,folha_privado.legacy_cutover,primeline_quadro_rollout.controlo IN ACCESS EXCLUSIVE MODE;
DO $private$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_quadro_b_20261011' AND nspowner='postgres'::regrole) OR (SELECT count(*) FROM primeline_quadro_b_20261011.snapshot)<>1 THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_quadro_b_20261011' AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.relnamespace='primeline_quadro_b_20261011'::regnamespace AND c.relkind IN('r','p') AND (a.grantee<>'postgres'::regrole OR c.relowner<>'postgres'::regrole OR NOT c.relrowsecurity))
 OR EXISTS(SELECT 1 FROM pg_attribute c JOIN pg_class r ON r.oid=c.attrelid CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE r.relnamespace='primeline_quadro_b_20261011'::regnamespace AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.pronamespace='primeline_quadro_b_20261011'::regnamespace AND (a.grantee<>'postgres'::regrole OR p.proowner<>'postgres'::regrole)) THEN RAISE EXCEPTION 'BACKUP_NOT_PRIVATE'; END IF;
END $private$;
DO $rollback$ DECLARE s primeline_quadro_b_20261011.snapshot; f jsonb; t jsonb; col jsonb; a jsonb; r record; grantee_sql text; c jsonb;
BEGIN
 SELECT * INTO STRICT s FROM primeline_quadro_b_20261011.snapshot WHERE singleton;
 IF s.state<>'applied' OR s.applied_catalog IS DISTINCT FROM primeline_quadro_b_20261011.catalog() OR (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'b' THEN RAISE EXCEPTION 'ROLLBACK_CATALOG_DRIFT'; END IF;
 SELECT value INTO f FROM jsonb_array_elements(s.catalog->'functions') WHERE value->>'signature'='fn_quadro_proteger_escrita()';
 EXECUTE f->>'definition';
 SELECT value INTO f FROM jsonb_array_elements(s.catalog->'functions') WHERE value->>'signature'='fn_quadro_operar(text,jsonb,boolean,text)';
 FOR r IN SELECT DISTINCT grantee FROM aclexplode((SELECT proacl FROM pg_proc WHERE oid='public.fn_quadro_operar(text,jsonb,boolean,text)'::regprocedure)) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text) FROM %s',CASE WHEN r.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(r.grantee)) END);
 END LOOP;
 FOR a IN SELECT value FROM jsonb_array_elements(f->'acl') LOOP
  grantee_sql:=CASE WHEN (a->>'grantee')::oid=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid((a->>'grantee')::oid)) END;
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text) TO '||grantee_sql||CASE WHEN (a->>'is_grantable')::boolean THEN ' WITH GRANT OPTION' ELSE '' END;
 END LOOP;
 FOR t IN SELECT value FROM jsonb_array_elements(s.catalog->'tables') WHERE value->>'name' IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP
  FOR r IN SELECT DISTINCT grantee FROM aclexplode((SELECT relacl FROM pg_class WHERE oid=(t->>'name')::regclass)) LOOP
   EXECUTE format('REVOKE ALL ON TABLE %s FROM %s',(t->>'name')::regclass,CASE WHEN r.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(r.grantee)) END);
  END LOOP;
  FOR a IN SELECT value FROM jsonb_array_elements(t->'acl') LOOP
   grantee_sql:=CASE WHEN (a->>'grantee')::oid=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid((a->>'grantee')::oid)) END;
   EXECUTE format('GRANT %s ON TABLE %s TO %s%s',a->>'privilege_type',(t->>'name')::regclass,grantee_sql,CASE WHEN (a->>'is_grantable')::boolean THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
  FOR col IN SELECT value FROM jsonb_array_elements(t->'columns') LOOP
   FOR r IN SELECT DISTINCT grantee FROM pg_attribute att CROSS JOIN LATERAL aclexplode(att.attacl) acl WHERE att.attrelid=(t->>'name')::regclass AND att.attname=col->>'name' LOOP
    EXECUTE format('REVOKE ALL (%I) ON TABLE %s FROM %s',col->>'name',(t->>'name')::regclass,CASE WHEN r.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(r.grantee)) END);
   END LOOP;
   FOR a IN SELECT value FROM jsonb_array_elements(col->'acl') LOOP
    grantee_sql:=CASE WHEN (a->>'grantee')::oid=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid((a->>'grantee')::oid)) END;
    EXECUTE format('GRANT %s (%I) ON TABLE %s TO %s%s',a->>'privilege_type',col->>'name',(t->>'name')::regclass,grantee_sql,CASE WHEN (a->>'is_grantable')::boolean THEN ' WITH GRANT OPTION' ELSE '' END);
   END LOOP;
  END LOOP;
 END LOOP;
 IF s.catalog IS DISTINCT FROM primeline_quadro_b_20261011.catalog() THEN RAISE EXCEPTION 'ROLLBACK_NOT_EXACT'; END IF;
 IF s.control-ARRAY['estado','fase_b_aplicada_em'] IS DISTINCT FROM (SELECT to_jsonb(x)-ARRAY['estado','fase_b_aplicada_em'] FROM primeline_quadro_rollout.controlo x WHERE singleton) THEN RAISE EXCEPTION 'ROLLBACK_INSTALLATION_DRIFT'; END IF;
 c:=s.control;
 UPDATE primeline_quadro_rollout.controlo SET estado=c->>'estado',fase_b_aplicada_em=(c->>'fase_b_aplicada_em')::timestamptz WHERE singleton;
 UPDATE primeline_quadro_b_20261011.snapshot SET state='rolled_back' WHERE singleton;
END $rollback$;
SELECT 'QUADRO_B_20261011_ROLLBACK_OK' resultado;
COMMIT;
