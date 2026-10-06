-- Independent, main-compatible RH metadata/Storage guard. No data/path migration.
BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR to_regnamespace('primeline_documentos_rh_backup') IS NULL THEN RAISE EXCEPTION 'OWNER_AND_PRIVATE_BACKUP_REQUIRED'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='documentos' AND public IS FALSE) THEN RAISE EXCEPTION 'PRIVATE_DOCUMENT_BUCKET_REQUIRED'; END IF; END $$;
CREATE SCHEMA primeline_documentos_rh_privado AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_documentos_rh_privado FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA primeline_documentos_rh_privado TO authenticated;
CREATE FUNCTION primeline_documentos_rh_privado.empresa(empresa uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.empresa_id=empresa)
$$;
CREATE FUNCTION primeline_documentos_rh_privado.entidade(tipo text,entidade uuid,empresa uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.empresa_id IS NOT NULL AND public.fn_e_administrativo()
 AND (empresa IS NULL OR empresa=u.empresa_id) AND (
 tipo='colaborador' AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=entidade AND c.empresa_id=u.empresa_id)
 OR tipo='viatura' AND EXISTS(SELECT 1 FROM public.viaturas v WHERE v.id=entidade AND v.empresa_id=u.empresa_id)
 OR tipo='ausencia' AND EXISTS(SELECT 1 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=entidade AND c.empresa_id=u.empresa_id)))
$$;
CREATE FUNCTION primeline_documentos_rh_privado.objeto(nome text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p text[]:=string_to_array(nome,'/'); BEGIN
 IF cardinality(p)<4 OR p[1]<>'rh' OR p[2] NOT IN('colaborador','viatura','ausencia') OR p[3] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 OR EXISTS(SELECT 1 FROM unnest(p) x WHERE x IN('','.', '..')) THEN RETURN false; END IF;
 RETURN primeline_documentos_rh_privado.entidade(p[2],p[3]::uuid,NULL);
END $$;
REVOKE ALL ON FUNCTION primeline_documentos_rh_privado.empresa(uuid),primeline_documentos_rh_privado.entidade(text,uuid,uuid),primeline_documentos_rh_privado.objeto(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION primeline_documentos_rh_privado.empresa(uuid),primeline_documentos_rh_privado.entidade(text,uuid,uuid),primeline_documentos_rh_privado.objeto(text) TO authenticated;
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ausencias_anexos ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
-- Restrictive AND closes every existing permissive OR path, preserving non-RH work access.
CREATE POLICY rh_empresa_guard ON public.documentos AS RESTRICTIVE FOR ALL TO authenticated
 USING(primeline_documentos_rh_privado.empresa(empresa_id) AND (entidade_tipo NOT IN('colaborador','viatura') OR primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id)))
 WITH CHECK(primeline_documentos_rh_privado.empresa(empresa_id) AND (entidade_tipo NOT IN('colaborador','viatura') OR primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id)));
CREATE POLICY rh_anexo_empresa_guard ON public.ausencias_anexos AS RESTRICTIVE FOR ALL TO authenticated
 USING(primeline_documentos_rh_privado.entidade('ausencia',ausencia_id,NULL)) WITH CHECK(primeline_documentos_rh_privado.entidade('ausencia',ausencia_id,NULL));
CREATE POLICY rh_storage_empresa_guard ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
 USING(bucket_id<>'documentos' OR NOT(name='rh' OR name LIKE 'rh/%') OR primeline_documentos_rh_privado.objeto(name))
 WITH CHECK(bucket_id<>'documentos' OR NOT(name='rh' OR name LIKE 'rh/%') OR primeline_documentos_rh_privado.objeto(name));
-- Tighten the dedicated permissive policy as well; no new Storage operations are granted.
DROP POLICY IF EXISTS pl_documentos_rh ON public.documentos;
CREATE POLICY pl_documentos_rh ON public.documentos FOR ALL TO authenticated
 USING(entidade_tipo IN('colaborador','viatura') AND primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id))
 WITH CHECK(entidade_tipo IN('colaborador','viatura') AND primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id));
-- Immutable installation evidence in the already private backup namespace.
-- Captured only by this reviewed transaction, never refreshed by postcheck.
CREATE TABLE primeline_documentos_rh_backup.instalacao AS
SELECT jsonb_build_object(
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects')),
 'tables',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'acl',c.relacl,'columns',(SELECT jsonb_agg(jsonb_build_object('name',attname,'acl',attacl) ORDER BY attnum) FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped)) ORDER BY c.oid) FROM pg_class c WHERE c.oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass)),
 'helpers',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl,'config',p.proconfig) ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.pronamespace='primeline_documentos_rh_privado'::regnamespace OR p.oid IN('public.fn_utilizador_atual_id()'::regprocedure,'public.fn_e_administrativo()'::regprocedure)),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',nspowner,'acl',nspacl) ORDER BY nspname) FROM pg_namespace WHERE nspname='primeline_documentos_rh_privado'),
 'bucket',(SELECT jsonb_agg(to_jsonb(b)) FROM storage.buckets b WHERE id='documentos')
) AS catalogo;
REVOKE ALL ON primeline_documentos_rh_backup.instalacao FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
