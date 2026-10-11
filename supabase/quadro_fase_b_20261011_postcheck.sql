-- READ ONLY. Data equality is an immediate post-migration check, before resuming writes.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $private$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_quadro_b_20261011' AND nspowner='postgres'::regrole) OR (SELECT count(*) FROM primeline_quadro_b_20261011.snapshot)<>1 THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_quadro_b_20261011' AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.relnamespace='primeline_quadro_b_20261011'::regnamespace AND c.relkind IN('r','p') AND (a.grantee<>'postgres'::regrole OR c.relowner<>'postgres'::regrole OR NOT c.relrowsecurity))
 OR EXISTS(SELECT 1 FROM pg_attribute c JOIN pg_class r ON r.oid=c.attrelid CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE r.relnamespace='primeline_quadro_b_20261011'::regnamespace AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.pronamespace='primeline_quadro_b_20261011'::regnamespace AND (a.grantee<>'postgres'::regrole OR p.proowner<>'postgres'::regrole)) THEN RAISE EXCEPTION 'BACKUP_NOT_PRIVATE'; END IF;
END $private$;
DO $invariants$ DECLARE before jsonb; after jsonb; f jsonb; actual jsonb; t jsonb; col jsonb; role_name text; priv text;
BEGIN
 IF (SELECT btrim(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.fn_quadro_proteger_escrita()'::regprocedure) IS DISTINCT FROM btrim($expected_guard$
DECLARE q public.quadro_pessoal_alocacao;
BEGIN
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id,NEW.colaborador_id,NEW.data) IS DISTINCT FROM (OLD.id,OLD.colaborador_id,OLD.data) THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: identidade imutável' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current() AND p.colaborador_id=q.colaborador_id AND p.data=q.data AND p.utilizador_id=public.fn_utilizador_atual_id()) THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: use o fluxo controlado' USING ERRCODE='42501'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $expected_guard$) THEN RAISE EXCEPTION 'GUARD_BODY_MISMATCH'; END IF;
 SELECT catalog INTO before FROM primeline_quadro_b_20261011.snapshot WHERE singleton;
 after:=primeline_quadro_b_20261011.catalog();
 IF jsonb_array_length(before->'functions')<>jsonb_array_length(after->'functions') OR jsonb_array_length(before->'tables')<>jsonb_array_length(after->'tables') THEN RAISE EXCEPTION 'UNEXPECTED_CATALOG_OBJECT_CHANGE'; END IF;
 FOR f IN SELECT value FROM jsonb_array_elements(before->'functions') LOOP
  SELECT value INTO actual FROM jsonb_array_elements(after->'functions') WHERE value->>'signature'=f->>'signature';
  IF f->>'signature'='fn_quadro_proteger_escrita()' THEN
   IF f-'definition' IS DISTINCT FROM actual-'definition' THEN RAISE EXCEPTION 'GUARD_METADATA_CHANGED'; END IF;
  ELSIF f->>'signature'='fn_quadro_operar(text,jsonb,boolean,text)' THEN
   IF f-'acl' IS DISTINCT FROM actual-'acl' THEN RAISE EXCEPTION 'OLD_RPC_BODY_CHANGED'; END IF;
  ELSIF f IS DISTINCT FROM actual THEN RAISE EXCEPTION 'PRESERVED_FUNCTION_CHANGED: %',f->>'signature'; END IF;
 END LOOP;
 FOR t IN SELECT value FROM jsonb_array_elements(before->'tables') LOOP
  SELECT value INTO actual FROM jsonb_array_elements(after->'tables') WHERE value->>'name'=t->>'name';
  IF t->>'name' IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') THEN
   IF t-ARRAY['acl','columns'] IS DISTINCT FROM actual-ARRAY['acl','columns'] THEN RAISE EXCEPTION 'POLICY_RLS_STRUCTURE_CHANGED: %',t->>'name'; END IF;
   FOR col IN SELECT value FROM jsonb_array_elements(t->'columns') LOOP
    IF col-'acl' IS DISTINCT FROM (SELECT value-'acl' FROM jsonb_array_elements(actual->'columns') WHERE value->>'name'=col->>'name') THEN RAISE EXCEPTION 'COLUMN_STRUCTURE_CHANGED'; END IF;
   END LOOP;
   -- Effective reads must stay unchanged, including column SELECT grants.
   IF (SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(t->'acl') WHERE value->>'privilege_type'='SELECT') IS DISTINCT FROM (SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(actual->'acl') WHERE value->>'privilege_type'='SELECT') THEN RAISE EXCEPTION 'READ_GRANTS_CHANGED'; END IF;
   FOR col IN SELECT value FROM jsonb_array_elements(t->'columns') LOOP
    IF (SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(col->'acl') WHERE value->>'privilege_type'='SELECT') IS DISTINCT FROM (SELECT jsonb_agg(a.value ORDER BY a.value::text) FROM jsonb_array_elements(actual->'columns') c CROSS JOIN LATERAL jsonb_array_elements(c.value->'acl') a WHERE c.value->>'name'=col->>'name' AND a.value->>'privilege_type'='SELECT') THEN RAISE EXCEPTION 'COLUMN_READ_CHANGED'; END IF;
   END LOOP;
  ELSIF t IS DISTINCT FROM actual THEN RAISE EXCEPTION 'PRESERVED_TABLE_CHANGED: %',t->>'name'; END IF;
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH priv IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(role_name,'public.quadro_pessoal_alocacao',priv) OR has_table_privilege(role_name,'public.quadro_pessoal_movimentos',priv) THEN RAISE EXCEPTION 'LEGACY_DML_STILL_GRANTED: %, %',role_name,priv; END IF;
  END LOOP;
  IF has_function_privilege(role_name,'public.fn_quadro_operar(text,jsonb,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'LEGACY_RPC_STILL_GRANTED'; END IF;
  IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND attnum>0 AND NOT attisdropped AND (has_column_privilege(role_name,attrelid,attname,'INSERT') OR has_column_privilege(role_name,attrelid,attname,'UPDATE') OR has_column_privilege(role_name,attrelid,attname,'REFERENCES'))) THEN RAISE EXCEPTION 'LEGACY_COLUMN_DML_STILL_GRANTED'; END IF;
 END LOOP;
END $invariants$;
DO $post$ BEGIN
 IF (SELECT state FROM primeline_quadro_b_20261011.snapshot WHERE singleton) IS DISTINCT FROM 'applied' OR (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'b' THEN RAISE EXCEPTION 'B_NOT_INSTALLED'; END IF;
 IF (SELECT control-ARRAY['estado','fase_b_aplicada_em'] FROM primeline_quadro_b_20261011.snapshot WHERE singleton) IS DISTINCT FROM (SELECT to_jsonb(c)-ARRAY['estado','fase_b_aplicada_em'] FROM primeline_quadro_rollout.controlo c WHERE singleton) THEN RAISE EXCEPTION 'INSTALLATION_IDENTITY_CHANGED'; END IF;
 IF (SELECT applied_catalog FROM primeline_quadro_b_20261011.snapshot WHERE singleton) IS DISTINCT FROM primeline_quadro_b_20261011.catalog() THEN RAISE EXCEPTION 'APPLIED_CATALOG_DRIFT'; END IF;
 IF (SELECT data_hashes FROM primeline_quadro_b_20261011.snapshot WHERE singleton) IS DISTINCT FROM primeline_quadro_b_20261011.data_hashes() THEN RAISE EXCEPTION 'OPERATIONAL_DATA_CHANGED'; END IF;
END $post$;
SELECT 'QUADRO_B_20261011_POSTCHECK_OK' resultado;
COMMIT;
