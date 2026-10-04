-- Somente leitura. Verifica instalação e preservação integral do catálogo fora da lista autorizada.
BEGIN READ ONLY;
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
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),'')) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p'))
));
 IF a IS NULL OR live IS DISTINCT FROM a THEN RAISE EXCEPTION 'POSTCHECK_CATALOG_DRIFT'; END IF;
 -- Compara TODAS as tabelas, excetuando apenas as duas novas policies.
 SELECT jsonb_agg(t||jsonb_build_object('policies',
  (SELECT jsonb_agg(p ORDER BY p->>'name') FROM jsonb_array_elements(nullif(t->'policies','null'::jsonb)) p
   WHERE p->>'name'<>'encarregado_sem_select_direto')) ORDER BY t->>'name')
 INTO x FROM jsonb_array_elements(live->'tables') t;
 SELECT jsonb_agg(t ORDER BY t->>'name') INTO y FROM jsonb_array_elements(b->'tables') t;
 IF x IS DISTINCT FROM y THEN RAISE EXCEPTION 'LEGACY_TABLE_CATALOG_CHANGED'; END IF;
 SELECT jsonb_agg(f ORDER BY f->>'signature') INTO x FROM jsonb_array_elements(live->'functions') f
 WHERE f->>'signature' NOT IN('fn_encarregado_acesso_direto_bloqueado()','fn_subempreitadas_operacionais_obra(uuid)','fn_quadro_contexto_v1(date,date)','fn_equipa_obra_encarregado(date,uuid)','fn_quadro_ferias_encarregado_global(date,date)');
 SELECT jsonb_agg(f ORDER BY f->>'signature') INTO y FROM jsonb_array_elements(b->'functions') f
 WHERE f->>'signature' NOT IN('fn_quadro_contexto_v1(date,date)','fn_equipa_obra_encarregado(date,uuid)','fn_quadro_ferias_encarregado_global(date,date)');
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
 RAISE NOTICE 'POSTCHECK_ENCARREGADO_OK';
END $post$;
-- Exercita as identidades reais apenas em SELECT, sem emitir dados/PII.
-- As claims e o papel são locais à transação; o ROLLBACK repõe a sessão.
DO $roles$
DECLARE r record; n bigint; blocked boolean; works uuid[]; work uuid;
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
   FOREACH work IN ARRAY coalesce(works,'{}'::uuid[]) LOOP
    SELECT count(*) INTO n FROM public.fn_subempreitadas_operacionais_obra(work) s WHERE s.obra_id<>work;
    IF n<>0 THEN RAISE EXCEPTION 'OPERATIONAL_SCOPE_INVALID'; END IF;
   END LOOP;
  END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
 RAISE NOTICE 'POSTCHECK_ROLES_OK';
END $roles$;
ROLLBACK;
