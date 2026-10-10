BEGIN;
CREATE SCHEMA primeline_equipa_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_equipa_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_equipa_backup.funcoes AS
SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proowner owner_oid,p.proacl acl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='folha_privado' AND p.proname IN('linha','save','local','normal')) OR (n.nspname='public' AND p.proname IN('fn_folha_contexto_v2','fn_folha_pessoas_v2','fn_folha_operar_v2','fn_quadro_resolver_data','fn_quadro_operar_v1','fn_quadro_contexto_v1','fn_folha_gestao_v2','fn_folha_gestao_contexto_v2'));
CREATE TABLE primeline_equipa_backup.legado(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
CREATE TABLE primeline_equipa_backup.catalogo AS
SELECT c.oid tabela_oid,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
 (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.policyname),'[]') FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname) policies,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('oid',t.oid,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.oid),'[]') FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal) triggers,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('oid',k.oid,'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid),'[]') FROM pg_constraint k WHERE k.conrelid=c.oid) constraints,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum),'[]') FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) colunas
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r';
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['colaboradores','obras','utilizadores','quadro_pessoal_alocacao','quadro_pessoal_movimentos','folha_registos','folha_historico','folha_externos_dias','ausencias','ponto_pessoal_obra'] LOOP
  EXECUTE format('INSERT INTO primeline_equipa_backup.legado SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
 END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_equipa_backup FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
