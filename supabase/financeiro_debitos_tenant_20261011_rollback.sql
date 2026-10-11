
-- MANUAL ONLY. Installation rollback is forbidden after any new financial fact/import.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
LOCK TABLE public.debitos_diretos,public.debitos_diretos_lancamentos,financeiro_debitos_privado.operacoes,financeiro_debitos_privado.grupos IN ACCESS EXCLUSIVE MODE;
DO $stop$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_debitos_20261011.controlo WHERE state='applied' AND singleton) THEN RAISE EXCEPTION 'APPLIED_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM financeiro_debitos_privado.operacoes) OR EXISTS(SELECT 1 FROM financeiro_debitos_privado.grupos) THEN RAISE EXCEPTION 'STOP_NEW_FINANCIAL_OPERATIONS'; END IF;
 IF (SELECT data_debitos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(d)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos d) OR (SELECT data_lancamentos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(l)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos_lancamentos l) THEN RAISE EXCEPTION 'STOP_NEW_OR_CHANGED_FINANCIAL_FACTS'; END IF;
END $stop$;
DROP FUNCTION public.fn_despesas_gerais_reverter_v1(uuid,uuid,text,boolean,text);
DROP FUNCTION public.fn_despesas_gerais_importar_v1(integer,jsonb,text,uuid,boolean,text,boolean);
DROP POLICY ddl_tenant_restrito ON public.debitos_diretos_lancamentos;
DROP POLICY dd_tenant_restrito ON public.debitos_diretos;
DROP TRIGGER trg_00_ddl_tenant ON public.debitos_diretos_lancamentos;
DROP TRIGGER trg_00_dd_tenant ON public.debitos_diretos;
DROP FUNCTION financeiro_debitos_privado.guarda();
DROP FUNCTION public.fn_debitos_tenant_leitura(uuid,uuid);
DROP FUNCTION financeiro_debitos_privado.snapshot(uuid);
DROP FUNCTION financeiro_debitos_privado.mac(text);
DROP FUNCTION financeiro_debitos_privado.ator();
DROP TABLE financeiro_debitos_privado.operacoes;
DROP TABLE financeiro_debitos_privado.grupos;
DROP TABLE financeiro_debitos_privado.config;
DROP SCHEMA financeiro_debitos_privado;
ALTER TABLE public.debitos_diretos_lancamentos DROP CONSTRAINT ddl_parent_empresa;
DROP INDEX public.dd_id_empresa_unique;
ALTER TABLE public.debitos_diretos_lancamentos DROP COLUMN empresa_id;
ALTER TABLE public.debitos_diretos DROP COLUMN empresa_id;
DO $acl$ DECLARE item record; n text; source aclitem[]; BEGIN
 FOREACH n IN ARRAY ARRAY['debitos_diretos','debitos_diretos_lancamentos'] LOOP
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role',n);
  IF n='debitos_diretos_lancamentos' THEN REVOKE ALL ON public.debitos_diretos_lancamentos FROM PUBLIC,anon,authenticated,service_role; END IF;
  SELECT CASE WHEN n='debitos_diretos' THEN acl_debitos ELSE acl_lancamentos END INTO source FROM primeline_debitos_20261011.controlo;
  FOR item IN SELECT * FROM aclexplode(source) WHERE grantee<>'postgres'::regrole LOOP
   EXECUTE format('GRANT %s ON public.%I TO %s%s',item.privilege_type,n,CASE WHEN item.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(item.grantee)) END,CASE WHEN item.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
END $acl$;
UPDATE primeline_debitos_20261011.controlo SET state='rolled_back' WHERE singleton;
SELECT 'FINANCEIRO_DEBITOS_ROLLBACK_OK' resultado;
COMMIT;
