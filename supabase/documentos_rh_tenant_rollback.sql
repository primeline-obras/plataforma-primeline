BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF; END $$;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.documentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR to_regnamespace('primeline_documentos_rh_backup') IS NULL THEN RAISE EXCEPTION 'OWNER_AND_PRIVATE_BACKUP_REQUIRED'; END IF; END $$;
DROP POLICY pl_documentos_rh ON public.documentos;
DO $$ DECLARE p record; r record; BEGIN
 FOR p IN SELECT * FROM primeline_documentos_rh_backup.policies WHERE schemaname='public' AND tablename='documentos' AND policyname='pl_documentos_rh' LOOP
  EXECUTE format('CREATE POLICY %I ON public.documentos AS %s FOR %s TO %s%s%s',p.policyname,p.permissive,p.cmd,(SELECT string_agg(quote_ident(x),',') FROM unnest(p.roles) x),CASE WHEN p.qual IS NULL THEN '' ELSE ' USING ('||p.qual||')' END,CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK ('||p.with_check||')' END);
 END LOOP;
END $$;
-- Safe compatibility rollback: restore the old permissive RH policy under the
-- SAME restrictive tenant guards. RLS, helpers and private evidence remain.
-- Removing this security overlay requires a separately reviewed replacement.
COMMIT;
