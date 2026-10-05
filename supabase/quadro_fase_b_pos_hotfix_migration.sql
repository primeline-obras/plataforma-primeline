BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;DO $gate$
DECLARE approved jsonb; actual jsonb;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF to_regclass('primeline_pacote2_gate.aprovacao') IS NULL THEN RAISE EXCEPTION 'REAL CATALOG VALIDATION REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_pacote2_gate' AND nspowner='postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_pacote2_gate' AND x.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.oid='primeline_pacote2_gate.aprovacao'::regclass AND (c.relowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole))
 OR EXISTS(SELECT 1 FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) x WHERE a.attrelid='primeline_pacote2_gate.aprovacao'::regclass AND x.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'GATE_NOT_PRIVATE'; END IF;
 EXECUTE 'SELECT CASE WHEN count(*)=1 THEN jsonb_agg(to_jsonb(x))->0 END FROM primeline_pacote2_gate.aprovacao x' INTO approved;
 IF approved IS NULL OR approved->>'release_id' IS DISTINCT FROM 'pacote2_folha_v2_20261005'
 OR approved->>'reviewed_by' IS DISTINCT FROM 'postgres' OR approved->>'consumed_at' IS NOT NULL
 OR approved->>'frontend_assets_sha256' IS NULL OR approved->>'frontend_assets_sha256' !~ '^[0-9a-f]{64}$'
 OR (approved->>'frontend_validated')::boolean IS DISTINCT FROM true
 OR (approved->>'backend_v2_validated')::boolean IS DISTINCT FROM true
 OR (approved->>'reviewed_at')::timestamptz IS NULL OR (approved->>'reviewed_at')::timestamptz>now()
 THEN RAISE EXCEPTION 'POST_HOTFIX_VALIDATION_REQUIRED'; END IF;
 IF (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'a'
 OR (SELECT instalacao_id::text FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM approved->>'installation_id'
 THEN RAISE EXCEPTION 'INSTALLATION_MISMATCH'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.quadro_pessoal_alocacao'::regclass AND polname='encarregado_sem_dml_direto' AND NOT polpermissive AND polcmd='*'
 AND pg_get_expr(polqual,polrelid)='(NOT fn_encarregado_acesso_direto_bloqueado())' AND pg_get_expr(polwithcheck,polrelid)='(NOT fn_encarregado_acesso_direto_bloqueado())') THEN RAISE EXCEPTION 'HOTFIX_POLICY_REQUIRED'; END IF;
 actual:=(SELECT jsonb_build_object(
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','folha_privado') AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.policyname) FROM pg_policies x WHERE x.schemaname=n.nspname AND x.tablename=c.relname),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',x.tgname,'enabled',x.tgenabled,'definition',pg_get_triggerdef(x.oid)) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid AND NOT x.tgisinternal),
 'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY x.indexrelid::regclass::text) FROM pg_index x WHERE x.indrelid=c.oid)) ORDER BY c.oid::regclass::text COLLATE "C") FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','folha_privado') AND c.relkind IN('r','p'))));
 IF actual IS DISTINCT FROM approved->'expected_catalog' THEN RAISE EXCEPTION 'POST_HOTFIX_CATALOG_DRIFT'; END IF;
 IF to_regprocedure('public.fn_folha_operar_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'FOLHA_V2_REQUIRED'; END IF;
END $gate$;
DO $$ BEGIN
 IF to_regclass('primeline_quadro_b_20261005.aprovacao') IS NULL THEN RAISE EXCEPTION 'BACKUP_B_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.quadro_pessoal_alocacao x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.alocacoes x)
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.quadro_pessoal_movimentos x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.movimentos x)
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.ponto_pessoal_obra x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.ponto x)
 THEN RAISE EXCEPTION 'BACKUP_DATA_DRIFT'; END IF;
END $$;CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.quadro_pessoal_alocacao;
BEGIN
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id,NEW.colaborador_id,NEW.data) IS DISTINCT FROM (OLD.id,OLD.colaborador_id,OLD.data)
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: identidade imutável.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current()
 AND p.colaborador_id=q.colaborador_id AND p.data=q.data AND p.utilizador_id=public.fn_utilizador_atual_id())
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: use a operação controlada de alocação.' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 RAISE EXCEPTION 'CLIENT_UPGRADE_REQUIRED: recarregue o Quadro antes de editar.' USING ERRCODE='42501'; END $$;
-- Policies pós-hotfix ficam INTACTAS, incluindo a restritiva do Encarregado.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT attrelid::regclass tabela,attname FROM pg_attribute WHERE attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND attnum>0 AND NOT attisdropped LOOP
 EXECUTE format('REVOKE INSERT (%I),UPDATE (%I),REFERENCES (%I) ON TABLE %s FROM PUBLIC,anon,authenticated,service_role',c.attname,c.attname,c.attname,c.tabela);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
UPDATE primeline_quadro_rollout.controlo SET estado='b',fase_b_aplicada_em=clock_timestamp() WHERE singleton;
UPDATE primeline_pacote2_gate.aprovacao SET consumed_at=clock_timestamp();
-- Ponto legado permanece histórico e com a dívida de writer inventariada.
-- Fecho desse writer exige validação real v2 + plano explícito dos dias LEGACY_CONFLICT.
COMMIT;