-- Pós-instalação, antes da ativação. Read-only e fail-closed.
BEGIN READ ONLY;
SET LOCAL search_path=pg_catalog;
DO $$ DECLARE r record; rows_now jsonb; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_diaria_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_diaria_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'DAILY_BACKUP_NOT_PRIVATE'; END IF;
 IF to_regclass('public.folha_avaliacoes_diarias') IS NULL OR to_regclass('public.folha_horarios_versoes') IS NULL THEN RAISE EXCEPTION 'DAILY_SCHEMA_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias) OR EXISTS(SELECT 1 FROM public.folha_horarios_versoes) OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE avaliacao_diaria_data_ativacao IS NOT NULL) THEN RAISE EXCEPTION 'POSTCHECK_REQUIRES_PRE_ACTIVATION'; END IF;
 FOR r IN SELECT c.oid,c.relowner,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_horarios_versoes'::regclass) LOOP
  IF r.relowner<>'postgres'::regrole OR NOT r.relrowsecurity OR EXISTS(SELECT 1 FROM aclexplode(coalesce(r.relacl,acldefault('r',r.relowner))) acl WHERE acl.grantee<>r.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=r.oid) THEN RAISE EXCEPTION 'DAILY_ACL_OR_POLICY_DIVERGENCE'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.folha_horarios_versoes a JOIN public.folha_horarios_versoes b ON a.obra_id=b.obra_id AND a.id<b.id AND daterange(a.vigente_desde,a.vigente_ate,'[)') && daterange(b.vigente_desde,b.vigente_ate,'[)')) THEN RAISE EXCEPTION 'SCHEDULE_VERSION_OVERLAP'; END IF;
 FOR r IN SELECT * FROM primeline_diaria_backup.dados LOOP
  IF r.tabela='folha_config_empresa' THEN SELECT coalesce(jsonb_agg(to_jsonb(c)-ARRAY['avaliacao_diaria_data_ativacao','avaliacao_diaria_ativada_em','avaliacao_diaria_ativada_por','avaliacao_diaria_ativacao_request_id'] ORDER BY (to_jsonb(c)-ARRAY['avaliacao_diaria_data_ativacao','avaliacao_diaria_ativada_em','avaliacao_diaria_ativada_por','avaliacao_diaria_ativacao_request_id'])::text COLLATE "C"),'[]'::jsonb) INTO rows_now FROM public.folha_config_empresa c;
  ELSE EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now; END IF;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'DAILY_EXISTING_DATA_CHANGED: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]'::jsonb) FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]'::jsonb) FROM primeline_diaria_backup.operacoes x) THEN RAISE EXCEPTION 'DAILY_LEDGER_CHANGED'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]'::jsonb) FROM folha_privado.periodos_revisoes x) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]'::jsonb) FROM primeline_diaria_backup.periodos_revisoes x) THEN RAISE EXCEPTION 'DAILY_TOMBSTONE_CHANGED'; END IF;
 FOR r IN SELECT p.oid,p.proowner,p.prosecdef,p.proconfig,p.proacl,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname LIKE 'diaria_%' LOOP
  IF r.proowner<>'postgres'::regrole OR r.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR EXISTS(SELECT 1 FROM aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) acl WHERE acl.grantee<>r.proowner) THEN RAISE EXCEPTION 'DAILY_HELPER_SECURITY_DRIFT'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM (VALUES ('folha_diaria_factos','public.folha_registos'::regclass),('folha_diaria_ausencias','public.ausencias'::regclass),('folha_diaria_vencimentos','public.folha_avaliacoes_diarias'::regclass),('folha_diaria_integridade','public.folha_avaliacoes_diarias'::regclass),('folha_horario_versao_integridade','public.folha_horarios_versoes'::regclass),('folha_diaria_config_integridade','public.folha_config_empresa'::regclass),('folha_diaria_horario_integridade','public.folha_horarios'::regclass)) expected(name,rel) WHERE NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgname=expected.name AND t.tgrelid=expected.rel AND t.tgenabled='O')) THEN RAISE EXCEPTION 'DAILY_TRIGGER_MISSING_OR_DISABLED'; END IF;
END $$;
DO $$ DECLARE r record; f record; BEGIN
 FOR r IN SELECT * FROM (VALUES ('folha_privado.diaria_guardar()','440624d5c86058347cac07255bfd51fabcd88acde6c2e8887296bea33ff4b03c',false,false),
('folha_privado.diaria_pessoal(uuid,date)','03fb5ffb45b103bbc0c5cbcdbabad0fcc12ee28bc67aa3a065f8e5a6d1e82a27',false,false),
('folha_privado.diaria_referencia(uuid,date)','fa4c9436d48a1b3d6fbfe3ca6b3cb093a0a711893911756a245bb4deee7a417a',true,false),
('folha_privado.diaria_factos(uuid,date)','a5a358ea43d938bf2935b577a7cb0049532030b2b24dcb4b025d3446bd481db8',true,false),
('folha_privado.diaria_decisao_hash(text,integer,jsonb)','8fd6e4a7f725d6d72656e9c693f5f62b3cac669791c1cb2eaddf9cb8a588380d',false,false),
('folha_privado.diaria_recalcular(uuid,date,uuid)','9fd5bbf3050106ab8e51f5e833cd620267df0008bdf962b09dec914f05889aa1',true,false),
('folha_privado.diaria_reconciliar_trigger()','982b6808f69f55a0f2f9d42b259382d5df605f06423b49551b34e72b1728d63d',true,false),
('folha_privado.diaria_config_guardar()','d54e4916df22a509016a7a496205b85900dc830052a32fa9f76cdadc8d920202',false,false),
('public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)','189eb93caeea512629b5823403657032ddabab49358d9b66901caaf244d357fb',true,true),
('folha_privado.save(jsonb,uuid,date,uuid,boolean)','55fe8bdeb8a088560b35c832b6a3f7eaa447d20635c7b36115802f4cfa7f5c64',true,false),
('folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)','383e0418e07e24242e2d3d6fd1e0c86e6c96974a660e0d77c49a7302cb6e6d0b',true,false),
('folha_privado.operar_periodos(jsonb,boolean,text)','8485fa5e91cd889604ec673f77c6687fa53cbc0004d0b9b8635a1545bedcfb00',true,false),
('folha_privado.reconciliar_he(public.folha_registos)','02de40125f22581126e578462103b3cb11e1b1f93e47c16d26c10225b6d8d120',true,false),
('folha_privado.reconciliar_dia(uuid,date,uuid,text)','76db734ed6559168edc3e346fd55cf27c43a95e6b7c705d31d5f1534f6c98aa3',true,false),
('folha_privado.linha(uuid,uuid,date,text)','02a106e4d393d7c0aa86961018e94ac4159c3754ffee8555498b307bde3ea380',true,false),
('folha_privado.normal(uuid,uuid,date)','18402c32159f3c9decfea2dadade38b026307a51bd8e83571efe0b000767d053',true,false),
('folha_privado.payroll_facts(uuid,date)','95b73294972f4aad1da81bef1e78a52a112497ab32b60db1894ec1a4965f51d0',true,false),
('folha_privado.diaria_gestao_preservada(text,jsonb,boolean,text)','6f774d5927b0c30a03893dde98f4ceb1ec28650fbd7909c09ff7fd6de58ac19d',true,false),
('public.fn_folha_gestao_contexto_v2(uuid,uuid,date)','7b5ee125ea2120943095fbf156a46ce990fc2844a58b25355a154a82eb84540b',true,true),
('public.fn_folha_gestao_v2(text,jsonb,boolean,text)','3752c8498c131ecf8862862fcbc5a918ec984d86333a2ad2f77b029d8491e5f9',true,true)) expected(sig,hash,sd,is_rpc) LOOP
  SELECT p.*,pg_get_userbyid(p.proowner) owner INTO f FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig);
  IF f.oid IS NULL OR f.owner<>'postgres' OR f.prosecdef IS DISTINCT FROM r.sd OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR encode(sha256(convert_to(btrim(replace(f.prosrc,chr(13),''),E' \n\t'),'UTF8')),'hex')<>r.hash OR EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) acl WHERE acl.grantee<>f.proowner AND (NOT r.is_rpc OR acl.grantee<>'authenticated'::regrole OR acl.privilege_type<>'EXECUTE' OR acl.is_grantable)) OR r.is_rpc AND NOT has_function_privilege('authenticated',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'DAILY_FUNCTION_DIVERGENCE: %',r.sig; END IF;
 END LOOP;
END $$;
DO $$ DECLARE actual_catalog jsonb;BEGIN
-- Catálogo técnico normalizado, sem dados pessoais ou OIDs locais.
SELECT jsonb_agg(jsonb_build_object('table',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',k.conname,'definition',pg_get_constraintdef(k.oid),'validated',k.convalidated,'deferrable',k.condeferrable,'deferred',k.condeferred) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid)) FROM pg_index i WHERE i.indrelid=c.oid),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',t.tgname,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)) ORDER BY c.relname) catalogo
INTO actual_catalog FROM pg_class c WHERE c.oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_horarios_versoes'::regclass);
IF actual_catalog IS DISTINCT FROM $schema$[
  {
    "rls": true,
    "owner": "postgres",
    "table": "folha_avaliacoes_diarias",
    "columns": [
      {
        "name": "id",
        "type": "uuid",
        "default": "gen_random_uuid()",
        "not_null": true
      },
      {
        "name": "empresa_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "colaborador_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "data",
        "type": "date",
        "default": null,
        "not_null": true
      },
      {
        "name": "ativa",
        "type": "boolean",
        "default": "true",
        "not_null": true
      },
      {
        "name": "modo_dia",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "revision",
        "type": "integer",
        "default": null,
        "not_null": true
      },
      {
        "name": "referencia_estado",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "referencia_origem",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "referencia_revision",
        "type": "integer",
        "default": null,
        "not_null": true
      },
      {
        "name": "permanencia_id",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "obra_origem_id",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "horario_versao_id",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "permanencia_snapshot",
        "type": "jsonb",
        "default": null,
        "not_null": false
      },
      {
        "name": "horario_snapshot",
        "type": "jsonb",
        "default": null,
        "not_null": false
      },
      {
        "name": "contexto_snapshot",
        "type": "jsonb",
        "default": null,
        "not_null": true
      },
      {
        "name": "expected_minutes",
        "type": "integer",
        "default": null,
        "not_null": false
      },
      {
        "name": "referencia_motivo",
        "type": "text",
        "default": null,
        "not_null": false
      },
      {
        "name": "referencia_evidencia",
        "type": "jsonb",
        "default": null,
        "not_null": false
      },
      {
        "name": "capturado_por",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "capturado_em",
        "type": "timestamp with time zone",
        "default": null,
        "not_null": false
      },
      {
        "name": "captura_request_id",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "realizado_minutes",
        "type": "integer",
        "default": null,
        "not_null": true
      },
      {
        "name": "falta_minutes",
        "type": "integer",
        "default": null,
        "not_null": false
      },
      {
        "name": "excedente_minutes",
        "type": "integer",
        "default": null,
        "not_null": false
      },
      {
        "name": "estado",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "he_estado",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "pendencias",
        "type": "text[]",
        "default": "'{}'::text[]",
        "not_null": true
      },
      {
        "name": "factos_revisoes",
        "type": "jsonb",
        "default": null,
        "not_null": true
      },
      {
        "name": "factos_fingerprint",
        "type": "text",
        "default": null,
        "not_null": true
      },
      {
        "name": "fingerprint_version",
        "type": "text",
        "default": "'folha_factos_v1'::text",
        "not_null": true
      },
      {
        "name": "regra_avaliacao_version",
        "type": "text",
        "default": "'diaria_v1'::text",
        "not_null": true
      },
      {
        "name": "decisao_fingerprint",
        "type": "text",
        "default": null,
        "not_null": false
      },
      {
        "name": "he_decidido_por",
        "type": "uuid",
        "default": null,
        "not_null": false
      },
      {
        "name": "he_decidido_em",
        "type": "timestamp with time zone",
        "default": null,
        "not_null": false
      },
      {
        "name": "he_motivo",
        "type": "text",
        "default": null,
        "not_null": false
      },
      {
        "name": "criado_por",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "atualizado_por",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "criado_em",
        "type": "timestamp with time zone",
        "default": "now()",
        "not_null": true
      },
      {
        "name": "atualizado_em",
        "type": "timestamp with time zone",
        "default": "now()",
        "not_null": true
      },
      {
        "name": "avaliado_por",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "avaliado_em",
        "type": "timestamp with time zone",
        "default": "now()",
        "not_null": true
      },
      {
        "name": "request_id_inicial",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "ultimo_request_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      }
    ],
    "indexes": [
      "CREATE INDEX folha_diaria_competencia ON public.folha_avaliacoes_diarias USING btree (empresa_id, colaborador_id, data) WHERE ativa",
      "CREATE UNIQUE INDEX folha_avaliacoes_diarias_empresa_id_colaborador_id_data_key ON public.folha_avaliacoes_diarias USING btree (empresa_id, colaborador_id, data)",
      "CREATE UNIQUE INDEX folha_avaliacoes_diarias_pkey ON public.folha_avaliacoes_diarias USING btree (id)"
    ],
    "triggers": [
      {
        "name": "folha_diaria_integridade",
        "enabled": "O",
        "definition": "CREATE TRIGGER folha_diaria_integridade BEFORE INSERT OR DELETE OR UPDATE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_guardar()"
      },
      {
        "name": "folha_diaria_vencimentos",
        "enabled": "O",
        "definition": "CREATE TRIGGER folha_diaria_vencimentos AFTER INSERT OR UPDATE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos()"
      }
    ],
    "force_rls": false,
    "constraints": [
      {
        "name": "folha_avaliacoes_diarias_atualizado_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (atualizado_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_avaliado_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (avaliado_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_capturado_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (capturado_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((ativa = (estado <> 'inativa'::text)))"
      },
      {
        "name": "folha_avaliacoes_diarias_check1",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((num_nonnulls(falta_minutes, excedente_minutes) = ANY (ARRAY[0, 2])))"
      },
      {
        "name": "folha_avaliacoes_diarias_check2",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((falta_minutes IS NULL) OR ((expected_minutes IS NOT NULL) AND (falta_minutes = GREATEST(0, (expected_minutes - realizado_minutes))) AND (excedente_minutes = GREATEST(0, (realizado_minutes - expected_minutes))))))"
      },
      {
        "name": "folha_avaliacoes_diarias_check3",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((((referencia_estado = 'pendente'::text) AND (expected_minutes IS NULL) AND (NULLIF(btrim(referencia_motivo), ''::text) IS NOT NULL)) OR ((referencia_estado = 'capturada'::text) AND (expected_minutes IS NOT NULL) AND (horario_snapshot IS NOT NULL) AND (capturado_por IS NOT NULL) AND (capturado_em IS NOT NULL) AND (captura_request_id IS NOT NULL))))"
      },
      {
        "name": "folha_avaliacoes_diarias_check4",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((referencia_estado <> 'capturada'::text) OR (referencia_origem <> 'automatico'::text) OR (num_nonnulls(permanencia_id, obra_origem_id, horario_versao_id, permanencia_snapshot) = 4)))"
      },
      {
        "name": "folha_avaliacoes_diarias_check5",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((referencia_origem <> 'administrativo'::text) OR ((referencia_evidencia IS NOT NULL) AND (NULLIF(btrim(referencia_motivo), ''::text) IS NOT NULL))))"
      },
      {
        "name": "folha_avaliacoes_diarias_check6",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((((he_estado = ANY (ARRAY['validada'::text, 'nao_considerada'::text])) AND (excedente_minutes > 0) AND (num_nonnulls(decisao_fingerprint, he_decidido_por, he_decidido_em, he_motivo) = 4) AND (NULLIF(btrim(he_motivo), ''::text) IS NOT NULL)) OR ((he_estado <> ALL (ARRAY['validada'::text, 'nao_considerada'::text])) AND (num_nonnulls(decisao_fingerprint, he_decidido_por, he_decidido_em, he_motivo) = 0))))"
      },
      {
        "name": "folha_avaliacoes_diarias_check7",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((NOT ativa) OR (he_estado <> 'pendente'::text) OR ('he_diaria_pendente'::text = ANY (pendencias))))"
      },
      {
        "name": "folha_avaliacoes_diarias_check8",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((NOT ativa) OR (he_estado <> 'validada'::text) OR ('he_validada_aguarda_processamento'::text = ANY (pendencias))))"
      },
      {
        "name": "folha_avaliacoes_diarias_colaborador_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_criado_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (criado_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_decisao_fingerprint_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((decisao_fingerprint ~ '^[0-9a-f]{64}$'::text))"
      },
      {
        "name": "folha_avaliacoes_diarias_empresa_id_colaborador_id_data_key",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "UNIQUE (empresa_id, colaborador_id, data)"
      },
      {
        "name": "folha_avaliacoes_diarias_empresa_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (empresa_id) REFERENCES public.empresas(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_estado_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((estado = ANY (ARRAY['regular'::text, 'horas_em_falta'::text, 'potencial_he'::text, 'referencia_pendente'::text, 'intervalo_aberto'::text, 'conflito'::text, 'outras_pendencias'::text, 'inativa'::text])))"
      },
      {
        "name": "folha_avaliacoes_diarias_excedente_minutes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((excedente_minutes >= 0))"
      },
      {
        "name": "folha_avaliacoes_diarias_expected_minutes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((expected_minutes >= 1) AND (expected_minutes <= 1440)))"
      },
      {
        "name": "folha_avaliacoes_diarias_factos_fingerprint_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((factos_fingerprint ~ '^[0-9a-f]{64}$'::text))"
      },
      {
        "name": "folha_avaliacoes_diarias_factos_revisoes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((jsonb_typeof(factos_revisoes) = 'array'::text))"
      },
      {
        "name": "folha_avaliacoes_diarias_falta_minutes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((falta_minutes >= 0))"
      },
      {
        "name": "folha_avaliacoes_diarias_fingerprint_version_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((fingerprint_version = 'folha_factos_v1'::text))"
      },
      {
        "name": "folha_avaliacoes_diarias_he_decidido_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (he_decidido_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_avaliacoes_diarias_he_estado_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((he_estado = ANY (ARRAY['nenhum'::text, 'nao_avaliavel'::text, 'pendente'::text, 'validada'::text, 'nao_considerada'::text])))"
      },
      {
        "name": "folha_avaliacoes_diarias_he_motivo_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((length(he_motivo) <= 1000))"
      },
      {
        "name": "folha_avaliacoes_diarias_horario_versao_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (horario_versao_id) REFERENCES public.folha_horarios_versoes(id) ON DELETE RESTRICT"
      },
      {
        "name": "folha_avaliacoes_diarias_modo_dia_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((modo_dia = ANY (ARRAY['personalizado'::text, 'misto'::text])))"
      },
      {
        "name": "folha_avaliacoes_diarias_obra_origem_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (obra_origem_id) REFERENCES public.obras(id) ON DELETE RESTRICT"
      },
      {
        "name": "folha_avaliacoes_diarias_permanencia_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (permanencia_id) REFERENCES public.quadro_equipa_permanencias(id) ON DELETE RESTRICT"
      },
      {
        "name": "folha_avaliacoes_diarias_pkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "PRIMARY KEY (id)"
      },
      {
        "name": "folha_avaliacoes_diarias_realizado_minutes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((realizado_minutes >= 0) AND (realizado_minutes <= 1440)))"
      },
      {
        "name": "folha_avaliacoes_diarias_referencia_estado_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((referencia_estado = ANY (ARRAY['capturada'::text, 'pendente'::text])))"
      },
      {
        "name": "folha_avaliacoes_diarias_referencia_motivo_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((length(referencia_motivo) <= 1000))"
      },
      {
        "name": "folha_avaliacoes_diarias_referencia_origem_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((referencia_origem = ANY (ARRAY['automatico'::text, 'administrativo'::text])))"
      },
      {
        "name": "folha_avaliacoes_diarias_referencia_revision_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((referencia_revision > 0))"
      },
      {
        "name": "folha_avaliacoes_diarias_regra_avaliacao_version_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((regra_avaliacao_version = 'diaria_v1'::text))"
      },
      {
        "name": "folha_avaliacoes_diarias_revision_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((revision > 0))"
      }
    ]
  },
  {
    "rls": true,
    "owner": "postgres",
    "table": "folha_horarios_versoes",
    "columns": [
      {
        "name": "id",
        "type": "uuid",
        "default": "gen_random_uuid()",
        "not_null": true
      },
      {
        "name": "empresa_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "obra_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "revision",
        "type": "integer",
        "default": null,
        "not_null": true
      },
      {
        "name": "snapshot",
        "type": "jsonb",
        "default": null,
        "not_null": true
      },
      {
        "name": "vigente_desde",
        "type": "date",
        "default": null,
        "not_null": true
      },
      {
        "name": "vigente_ate",
        "type": "date",
        "default": null,
        "not_null": false
      },
      {
        "name": "criado_por",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "criado_em",
        "type": "timestamp with time zone",
        "default": "now()",
        "not_null": true
      },
      {
        "name": "request_id",
        "type": "uuid",
        "default": null,
        "not_null": true
      },
      {
        "name": "motivo",
        "type": "text",
        "default": null,
        "not_null": false
      }
    ],
    "indexes": [
      "CREATE INDEX folha_horarios_versoes_vigencia ON public.folha_horarios_versoes USING btree (empresa_id, obra_id, vigente_desde, vigente_ate)",
      "CREATE UNIQUE INDEX folha_horarios_versoes_obra_id_revision_key ON public.folha_horarios_versoes USING btree (obra_id, revision)",
      "CREATE UNIQUE INDEX folha_horarios_versoes_pkey ON public.folha_horarios_versoes USING btree (id)"
    ],
    "triggers": [
      {
        "name": "folha_horario_versao_integridade",
        "enabled": "O",
        "definition": "CREATE TRIGGER folha_horario_versao_integridade BEFORE INSERT OR DELETE OR UPDATE ON public.folha_horarios_versoes FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_guardar()"
      }
    ],
    "force_rls": false,
    "constraints": [
      {
        "name": "folha_horarios_versoes_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((vigente_ate IS NULL) OR (vigente_ate >= vigente_desde)))"
      },
      {
        "name": "folha_horarios_versoes_criado_por_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (criado_por) REFERENCES public.utilizadores(id)"
      },
      {
        "name": "folha_horarios_versoes_empresa_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (empresa_id) REFERENCES public.empresas(id)"
      },
      {
        "name": "folha_horarios_versoes_motivo_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((length(motivo) <= 1000))"
      },
      {
        "name": "folha_horarios_versoes_obra_id_fkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "FOREIGN KEY (obra_id) REFERENCES public.obras(id)"
      },
      {
        "name": "folha_horarios_versoes_obra_id_revision_key",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "UNIQUE (obra_id, revision)"
      },
      {
        "name": "folha_horarios_versoes_pkey",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "PRIMARY KEY (id)"
      },
      {
        "name": "folha_horarios_versoes_revision_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK ((revision > 0))"
      },
      {
        "name": "folha_horarios_versoes_snapshot_check",
        "deferred": false,
        "validated": true,
        "deferrable": false,
        "definition": "CHECK (((jsonb_typeof(snapshot) = 'object'::text) AND (snapshot ? 'intervals'::text) AND (snapshot ? 'expected_minutes'::text)))"
      }
    ]
  }
]
$schema$::jsonb THEN RAISE EXCEPTION 'DAILY_SCHEMA_DIVERGENCE';END IF;END $$;
SELECT 'DAILY_POSTCHECK_PASS_NOT_ACTIVATED' resultado;
COMMIT;