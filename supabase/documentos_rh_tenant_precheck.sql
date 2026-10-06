-- Local rollout material. Read-only; no Pacote 2 dependency.
BEGIN READ ONLY;
DO $$ DECLARE t text; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 FOREACH t IN ARRAY ARRAY['public.documentos','public.colaboradores','public.viaturas','public.ausencias','public.ausencias_anexos','public.utilizadores','storage.objects'] LOOP
  IF to_regclass(t) IS NULL THEN RAISE EXCEPTION 'DOCUMENT_SOURCE_REQUIRED: %',t; END IF;
 END LOOP;
 IF to_regprocedure('public.fn_utilizador_atual_id()') IS NULL OR to_regprocedure('public.fn_e_administrativo()') IS NULL THEN RAISE EXCEPTION 'CANONICAL_ACTOR_REQUIRED'; END IF;
 IF to_regnamespace('primeline_documentos_rh_privado') IS NOT NULL OR to_regnamespace('primeline_documentos_rh_backup') IS NOT NULL THEN RAISE EXCEPTION 'DOCUMENT_ROLLOUT_ALREADY_PRESENT'; END IF;
 IF EXISTS(SELECT 1 FROM public.documentos d WHERE d.entidade_tipo IN('colaborador','viatura') AND NOT (
  EXISTS(SELECT 1 FROM public.colaboradores c WHERE d.entidade_tipo='colaborador' AND c.id=d.entidade_id AND c.empresa_id=d.empresa_id)
  OR EXISTS(SELECT 1 FROM public.viaturas v WHERE d.entidade_tipo='viatura' AND v.id=d.entidade_id AND v.empresa_id=d.empresa_id)))
 THEN RAISE EXCEPTION 'RH_DOCUMENT_ENTITY_COMPANY_MISMATCH: reconcile explicitly before rollout'; END IF;
 IF EXISTS(SELECT 1 FROM public.ausencias_anexos an LEFT JOIN public.ausencias a ON a.id=an.ausencia_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE c.id IS NULL)
 THEN RAISE EXCEPTION 'RH_ATTACHMENT_ORPHAN'; END IF;
END $$;
-- Complete policy inventory, including permissive OR and restrictive AND.
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies
WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects') ORDER BY schemaname,tablename,policyname;
SELECT n.nspname,c.relname,c.relrowsecurity,c.relacl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname='public' AND c.relname IN('documentos','ausencias_anexos')) OR (n.nspname='storage' AND c.relname='objects');
ROLLBACK;
