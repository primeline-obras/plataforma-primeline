BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR to_regnamespace('primeline_documentos_rh_backup') IS NULL THEN RAISE EXCEPTION 'OWNER_AND_PRIVATE_BACKUP_REQUIRED'; END IF; END $$;
DROP POLICY rh_empresa_guard ON public.documentos;
DROP POLICY rh_anexo_empresa_guard ON public.ausencias_anexos;
DROP POLICY rh_storage_empresa_guard ON storage.objects;
DROP POLICY pl_documentos_rh ON public.documentos;
DO $$ DECLARE p record; r record; BEGIN
 FOR p IN SELECT * FROM primeline_documentos_rh_backup.policies WHERE schemaname='public' AND tablename='documentos' AND policyname='pl_documentos_rh' LOOP
  EXECUTE format('CREATE POLICY %I ON public.documentos AS %s FOR %s TO %s%s%s',p.policyname,p.permissive,p.cmd,(SELECT string_agg(quote_ident(x),',') FROM unnest(p.roles) x),CASE WHEN p.qual IS NULL THEN '' ELSE ' USING ('||p.qual||')' END,CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK ('||p.with_check||')' END);
 END LOOP;
 FOR r IN SELECT * FROM primeline_documentos_rh_backup.tables WHERE NOT relrowsecurity LOOP EXECUTE format('ALTER TABLE %s DISABLE ROW LEVEL SECURITY',r.oid::regclass); END LOOP;
END $$;
DROP FUNCTION primeline_documentos_rh_privado.objeto(text);
DROP FUNCTION primeline_documentos_rh_privado.entidade(text,uuid,uuid);
DROP FUNCTION primeline_documentos_rh_privado.empresa(uuid);
DROP SCHEMA primeline_documentos_rh_privado;
-- Backup intentionally preserved; rollback restores the former unsafe ACL only by explicit authorization.
COMMIT;
