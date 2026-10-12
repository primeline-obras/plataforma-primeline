-- Reversão estrutural sem destruir factos ou história. Recusa após qualquer uso do mecanismo.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
DO $$ DECLARE r record; rows_now jsonb; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regclass('primeline_diaria_backup.funcoes') IS NULL THEN RAISE EXCEPTION 'DAILY_BACKUP_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_diaria_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_diaria_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'DAILY_BACKUP_NOT_PRIVATE'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias) OR EXISTS(SELECT 1 FROM public.folha_horarios_versoes) OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE avaliacao_diaria_data_ativacao IS NOT NULL) THEN RAISE EXCEPTION 'DAILY_ROLLBACK_UNSAFE_AFTER_ACTIVATION: preservar snapshots e histórico; requer plano separado'; END IF;
 FOR r IN SELECT * FROM primeline_diaria_backup.dados LOOP
  EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',r.tabela);
  IF r.tabela='folha_config_empresa' THEN SELECT coalesce(jsonb_agg(to_jsonb(c)-ARRAY['avaliacao_diaria_data_ativacao','avaliacao_diaria_ativada_em','avaliacao_diaria_ativada_por','avaliacao_diaria_ativacao_request_id'] ORDER BY (to_jsonb(c)-ARRAY['avaliacao_diaria_data_ativacao','avaliacao_diaria_ativada_em','avaliacao_diaria_ativada_por','avaliacao_diaria_ativacao_request_id'])::text COLLATE "C"),'[]'::jsonb) INTO rows_now FROM public.folha_config_empresa c;
  ELSE EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now; END IF;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'DAILY_ROLLBACK_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
END $$;
DROP TRIGGER folha_diaria_factos ON public.folha_registos;
DROP TRIGGER folha_diaria_ausencias ON public.ausencias;
DROP TRIGGER folha_diaria_config_integridade ON public.folha_config_empresa;
DROP TRIGGER folha_diaria_horario_integridade ON public.folha_horarios;
DO $$ DECLARE r record; a record; BEGIN
 FOR r IN SELECT * FROM primeline_diaria_backup.funcoes ORDER BY assinatura LOOP
  EXECUTE r.definicao;
  EXECUTE format('ALTER FUNCTION %s OWNER TO %I',r.assinatura,pg_get_userbyid(r.owner_oid));
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',r.assinatura);
  FOR a IN SELECT * FROM aclexplode(coalesce(r.acl,acldefault('f',r.owner_oid))) LOOP
   EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',a.privilege_type,r.assinatura,CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END,CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
END $$;
DROP TABLE public.folha_avaliacoes_diarias;
DROP TABLE public.folha_horarios_versoes;
DROP FUNCTION public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text);
DROP FUNCTION folha_privado.diaria_guardar(),folha_privado.diaria_pessoal(uuid,date),folha_privado.diaria_referencia(uuid,date),folha_privado.diaria_factos(uuid,date),folha_privado.diaria_decisao_hash(text,integer,jsonb),folha_privado.diaria_recalcular(uuid,date,uuid),folha_privado.diaria_reconciliar_trigger(),folha_privado.diaria_config_guardar(),folha_privado.diaria_gestao_preservada(text,jsonb,boolean,text);
ALTER TABLE public.folha_config_empresa DROP CONSTRAINT folha_diaria_ativacao_completa,
 DROP COLUMN avaliacao_diaria_data_ativacao,DROP COLUMN avaliacao_diaria_ativada_em,DROP COLUMN avaliacao_diaria_ativada_por,DROP COLUMN avaliacao_diaria_ativacao_request_id;
ALTER TABLE public.folha_gestao_historico DROP CONSTRAINT folha_gestao_historico_action_check;
DO $$ DECLARE definition text; BEGIN
 SELECT k->>'definition' INTO definition FROM primeline_diaria_backup.catalogo c CROSS JOIN LATERAL jsonb_array_elements(c.constraints) k WHERE c.relname='folha_gestao_historico' AND k->>'name'='folha_gestao_historico_action_check';
 IF definition IS NULL THEN RAISE EXCEPTION 'DAILY_ROLLBACK_CONSTRAINT_BACKUP_MISSING'; END IF;
 EXECUTE 'ALTER TABLE public.folha_gestao_historico ADD CONSTRAINT folha_gestao_historico_action_check '||definition;
END $$;
-- Backup privado preservado para auditoria. Não se elimina qualquer linha de negócio.
SELECT 'DAILY_ROLLBACK_PASS' resultado;
COMMIT;