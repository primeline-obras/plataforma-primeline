-- LOCAL: ainda não autorizado para produção. Não altera dados operacionais.
BEGIN;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.colaboradores, public.subempreitadas IN SHARE ROW EXCLUSIVE MODE;
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
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 IF md5(v::text) <> 'ad93cec96f207f7e622c41821eb38cf0' THEN RAISE EXCEPTION 'CATALOG_DRIFT: interromper e repetir diagnóstico'; END IF;
END $check$;

DO $private$
BEGIN
 IF (SELECT nspowner<> 'postgres'::regrole FROM pg_namespace WHERE nspname='primeline_encarregado_20261004')
 OR NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_encarregado_20261004') THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<> 'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
 IF (SELECT count(*) FROM primeline_encarregado_20261004.snapshot)<>1
 OR (SELECT md5(catalogo::text) FROM primeline_encarregado_20261004.snapshot)<>'ad93cec96f207f7e622c41821eb38cf0' THEN RAISE EXCEPTION 'BACKUP_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute x JOIN pg_class c ON c.oid=x.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(x.attacl) a WHERE n.nspname='primeline_encarregado_20261004' AND a.grantee<>'postgres'::regrole) THEN RAISE EXCEPTION 'BACKUP_ACL_INVALID'; END IF;
END $private$;

-- Uma policy restritiva participa por AND: outra permissiva não reabre SELECT.
-- Não se revoga SELECT de authenticated, que é partilhado por todos os perfis.
CREATE FUNCTION public.fn_encarregado_acesso_direto_bloqueado()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u
 WHERE u.id=public.fn_utilizador_atual_id() AND u.funcao='encarregado');
$function$;
REVOKE ALL ON FUNCTION public.fn_encarregado_acesso_direto_bloqueado() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_encarregado_acesso_direto_bloqueado() TO authenticated;
CREATE POLICY encarregado_sem_select_direto ON public.colaboradores AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());
CREATE POLICY encarregado_sem_select_direto ON public.subempreitadas AS RESTRICTIVE
 FOR SELECT TO authenticated USING (NOT public.fn_encarregado_acesso_direto_bloqueado());

-- O contexto mantém a temporalidade e os restantes campos; só retira o bypass global.
CREATE OR REPLACE FUNCTION public.fn_quadro_contexto_v1(p_inicio date, p_fim date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE u public.utilizadores; v_allocations jsonb; v_revisions jsonb; v_read jsonb; v_edit jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 IF NOT public.fn_quadro_pode_consultar_v1() THEN RAISE EXCEPTION 'PERMISSION_DENIED: sem responsabilidade autorizada para consultar o Quadro.' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>93 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo inválido.'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.data,q.id),'[]') INTO v_allocations
 FROM generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') d(data)
 CROSS JOIN LATERAL public.fn_quadro_resolver_data(d.data::date) q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND q.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR (q.tipo_alocacao='obra' AND public.fn_quadro_ler_obra(q.obra_id)));
 SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') INTO v_revisions FROM public.quadro_dias_revisoes d
 JOIN public.colaboradores c ON c.id=d.colaborador_id WHERE c.empresa_id=u.empresa_id AND d.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM unnest(d.obras_visiveis) w(id) WHERE public.fn_quadro_ler_obra(w.id)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a
 WHERE (a->>'colaborador_id')::uuid=d.colaborador_id AND (a->>'data')::date=d.data));
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_read FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id);
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_edit FROM public.obras o WHERE o.empresa_id=u.empresa_id AND (public.fn_quadro_pode_gerir_v1(o.id) OR public.fn_quadro_minha_obra_v1(o.id));
 RETURN jsonb_build_object('version',1,'allocations',v_allocations,'revisions',v_revisions,
 'can_manage_global',public.fn_quadro_pode_gerir_v1(NULL),'read_work_ids',v_read,'edit_work_ids',v_edit,
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'funcao',c.funcao,'data_admissao',c.data_admissao,'data_saida',c.data_saida) ORDER BY c.nome),'[]') FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND c.data_saida IS NULL AND (
 public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a WHERE (a->>'colaborador_id')::uuid=c.id))),
 'works',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'numero',o.numero,'nome',o.nome,'situacao',o.situacao) ORDER BY o.numero),'[]') FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id)));
END $function$;


-- Sem consumidor no frontend atual; ambas reservadas ao Encarregado, mas devolviam
-- pessoas globais/candidatos fora da equipa. Não criar o futuro seletor do Pacote 2.
REVOKE EXECUTE ON FUNCTION public.fn_quadro_ferias_encarregado_global(date,date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid) FROM authenticated;

-- Projeção exata utilizada por RNC, sem custo, valor ou condição de pagamento.
CREATE FUNCTION public.fn_subempreitadas_operacionais_obra(p_obra_id uuid)
RETURNS TABLE(id uuid, obra_id uuid, fornecedor_id uuid, especialidade text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE u public.utilizadores;
BEGIN
 SELECT * INTO u FROM public.utilizadores
 WHERE utilizadores.id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR p_obra_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=u.empresa_id
 ) THEN RAISE EXCEPTION 'PERMISSION_DENIED: obra indisponível.' USING ERRCODE='42501'; END IF;
 IF u.funcao='encarregado' THEN
   IF NOT public.fn_quadro_minha_obra(p_obra_id) THEN
     RAISE EXCEPTION 'PERMISSION_DENIED: obra não atribuída.' USING ERRCODE='42501';
   END IF;
 ELSIF NOT public.fn_pode_ver_obra(p_obra_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: sem acesso à obra.' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT s.id,s.obra_id,s.fornecedor_id,s.especialidade
 FROM public.subempreitadas s WHERE s.obra_id=p_obra_id ORDER BY s.especialidade,s.id;
END $function$;
REVOKE ALL ON FUNCTION public.fn_subempreitadas_operacionais_obra(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_subempreitadas_operacionais_obra(uuid) TO authenticated;

CREATE TABLE primeline_encarregado_20261004.instalacao(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), catalogo jsonb NOT NULL);
ALTER TABLE primeline_encarregado_20261004.instalacao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE primeline_encarregado_20261004.instalacao FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO primeline_encarregado_20261004.instalacao(catalogo) SELECT jsonb_build_object(
 'tables', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'options',c.reloptions,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'cmd',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END ORDER BY CASE WHEN roleid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(roleid) END) FROM unnest(p.polroles) roleid),'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
 'view_definition',CASE WHEN c.relkind IN('v','m') THEN pg_get_viewdef(c.oid,true) END) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p','v','m')),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
);
COMMIT;
