BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=pg_catalog;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_registos,public.folha_he,public.folha_vencimentos,public.folha_horarios_versoes,public.folha_config_empresa,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $gate$ DECLARE c jsonb;bad text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex')<>'e5dc4c1c3aea0720fcf142e4d52121c40e61d0b1308f87a81e23f5eaf66f2fef' THEN RAISE EXCEPTION 'AD14_AD15_REQUIRED_OR_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD14_AD15_METADATA_DRIFT'; END IF;
 IF to_regprocedure('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.diaria_ad14_final()') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape') OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final') THEN RAISE EXCEPTION 'AD14_INSTALLED_OR_PARTIAL'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.folha_avaliacoes_diarias'::regclass AND relowner='postgres'::regrole AND relrowsecurity) OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.oid='public.folha_avaliacoes_diarias'::regclass AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_avaliacoes_diarias'::regclass AND attnum>0 AND NOT attisdropped AND attacl IS NOT NULL AND attacl<>'{}'::aclitem[]) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.folha_avaliacoes_diarias'::regclass) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_integridade' AND tgenabled='O') THEN RAISE EXCEPTION 'AD14_TABLE_SECURITY_DRIFT'; END IF;
 IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass)<>39 THEN RAISE EXCEPTION 'AD14_BASELINE_CONSTRAINT_COUNT_DRIFT'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements($baseline$[{"name":"folha_avaliacoes_diarias_atualizado_por_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (atualizado_por) REFERENCES public.utilizadores(id)"},{"name":"folha_avaliacoes_diarias_avaliado_por_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (avaliado_por) REFERENCES public.utilizadores(id)"},{"name":"folha_avaliacoes_diarias_capturado_por_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (capturado_por) REFERENCES public.utilizadores(id)"},{"name":"folha_avaliacoes_diarias_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((ativa = (estado <> 'inativa'::text)))"},{"name":"folha_avaliacoes_diarias_check1","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((num_nonnulls(falta_minutes, excedente_minutes) = ANY (ARRAY[0, 2])))"},{"name":"folha_avaliacoes_diarias_check2","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((falta_minutes IS NULL) OR ((expected_minutes IS NOT NULL) AND (falta_minutes = GREATEST(0, (expected_minutes - realizado_minutes))) AND (excedente_minutes = GREATEST(0, (realizado_minutes - expected_minutes))))))"},{"name":"folha_avaliacoes_diarias_check3","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((((referencia_estado = 'pendente'::text) AND (expected_minutes IS NULL) AND (NULLIF(btrim(referencia_motivo), ''::text) IS NOT NULL)) OR ((referencia_estado = 'capturada'::text) AND (expected_minutes IS NOT NULL) AND (horario_snapshot IS NOT NULL) AND (capturado_por IS NOT NULL) AND (capturado_em IS NOT NULL) AND (captura_request_id IS NOT NULL))))"},{"name":"folha_avaliacoes_diarias_check4","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((referencia_estado <> 'capturada'::text) OR (referencia_origem <> 'automatico'::text) OR (num_nonnulls(permanencia_id, obra_origem_id, horario_versao_id, permanencia_snapshot) = 4)))"},{"name":"folha_avaliacoes_diarias_check5","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((referencia_origem <> 'administrativo'::text) OR ((referencia_evidencia IS NOT NULL) AND (NULLIF(btrim(referencia_motivo), ''::text) IS NOT NULL))))"},{"name":"folha_avaliacoes_diarias_check6","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((((he_estado = ANY (ARRAY['validada'::text, 'nao_considerada'::text])) AND (excedente_minutes > 0) AND (num_nonnulls(decisao_fingerprint, he_decidido_por, he_decidido_em, he_motivo) = 4) AND (NULLIF(btrim(he_motivo), ''::text) IS NOT NULL)) OR ((he_estado <> ALL (ARRAY['validada'::text, 'nao_considerada'::text])) AND (num_nonnulls(decisao_fingerprint, he_decidido_por, he_decidido_em, he_motivo) = 0))))"},{"name":"folha_avaliacoes_diarias_check7","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((NOT ativa) OR (he_estado <> 'pendente'::text) OR ('he_diaria_pendente'::text = ANY (pendencias))))"},{"name":"folha_avaliacoes_diarias_check8","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((NOT ativa) OR (he_estado <> 'validada'::text) OR ('he_validada_aguarda_processamento'::text = ANY (pendencias))))"},{"name":"folha_avaliacoes_diarias_colaborador_id_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (colaborador_id) REFERENCES public.colaboradores(id)"},{"name":"folha_avaliacoes_diarias_criado_por_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (criado_por) REFERENCES public.utilizadores(id)"},{"name":"folha_avaliacoes_diarias_decisao_fingerprint_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((decisao_fingerprint ~ '^[0-9a-f]{64}$'::text))"},{"name":"folha_avaliacoes_diarias_empresa_id_colaborador_id_data_key","deferred":false,"validated":true,"deferrable":false,"definition":"UNIQUE (empresa_id, colaborador_id, data)"},{"name":"folha_avaliacoes_diarias_empresa_id_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (empresa_id) REFERENCES public.empresas(id)"},{"name":"folha_avaliacoes_diarias_estado_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((estado = ANY (ARRAY['regular'::text, 'horas_em_falta'::text, 'potencial_he'::text, 'referencia_pendente'::text, 'intervalo_aberto'::text, 'conflito'::text, 'outras_pendencias'::text, 'inativa'::text])))"},{"name":"folha_avaliacoes_diarias_excedente_minutes_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((excedente_minutes >= 0))"},{"name":"folha_avaliacoes_diarias_expected_minutes_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((expected_minutes >= 1) AND (expected_minutes <= 1440)))"},{"name":"folha_avaliacoes_diarias_factos_fingerprint_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((factos_fingerprint ~ '^[0-9a-f]{64}$'::text))"},{"name":"folha_avaliacoes_diarias_factos_revisoes_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((jsonb_typeof(factos_revisoes) = 'array'::text))"},{"name":"folha_avaliacoes_diarias_falta_minutes_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((falta_minutes >= 0))"},{"name":"folha_avaliacoes_diarias_fingerprint_version_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((fingerprint_version = 'folha_factos_v1'::text))"},{"name":"folha_avaliacoes_diarias_he_decidido_por_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (he_decidido_por) REFERENCES public.utilizadores(id)"},{"name":"folha_avaliacoes_diarias_he_estado_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((he_estado = ANY (ARRAY['nenhum'::text, 'nao_avaliavel'::text, 'pendente'::text, 'validada'::text, 'nao_considerada'::text])))"},{"name":"folha_avaliacoes_diarias_he_motivo_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((length(he_motivo) <= 1000))"},{"name":"folha_avaliacoes_diarias_horario_versao_id_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (horario_versao_id) REFERENCES public.folha_horarios_versoes(id) ON DELETE RESTRICT"},{"name":"folha_avaliacoes_diarias_modo_dia_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((modo_dia = ANY (ARRAY['personalizado'::text, 'misto'::text])))"},{"name":"folha_avaliacoes_diarias_obra_origem_id_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (obra_origem_id) REFERENCES public.obras(id) ON DELETE RESTRICT"},{"name":"folha_avaliacoes_diarias_permanencia_id_fkey","deferred":false,"validated":true,"deferrable":false,"definition":"FOREIGN KEY (permanencia_id) REFERENCES public.quadro_equipa_permanencias(id) ON DELETE RESTRICT"},{"name":"folha_avaliacoes_diarias_pkey","deferred":false,"validated":true,"deferrable":false,"definition":"PRIMARY KEY (id)"},{"name":"folha_avaliacoes_diarias_realizado_minutes_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK (((realizado_minutes >= 0) AND (realizado_minutes <= 1440)))"},{"name":"folha_avaliacoes_diarias_referencia_estado_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((referencia_estado = ANY (ARRAY['capturada'::text, 'pendente'::text])))"},{"name":"folha_avaliacoes_diarias_referencia_motivo_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((length(referencia_motivo) <= 1000))"},{"name":"folha_avaliacoes_diarias_referencia_origem_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((referencia_origem = ANY (ARRAY['automatico'::text, 'administrativo'::text])))"},{"name":"folha_avaliacoes_diarias_referencia_revision_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((referencia_revision > 0))"},{"name":"folha_avaliacoes_diarias_regra_avaliacao_version_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((regra_avaliacao_version = 'diaria_v1'::text))"},{"name":"folha_avaliacoes_diarias_revision_check","deferred":false,"validated":true,"deferrable":false,"definition":"CHECK ((revision > 0))"}]$baseline$::jsonb) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname=c->>'name' AND pg_get_constraintdef(oid)=c->>'definition' AND convalidated) THEN RAISE EXCEPTION 'AD14_BASELINE_CONSTRAINT_DRIFT: %',c->>'name'; END IF;
 END LOOP;
 SELECT string_agg(a.id::text,',' ORDER BY a.id) INTO bad FROM public.folha_avaliacoes_diarias a WHERE ((
 jsonb_typeof(a.contexto_snapshot)='object' AND a.contexto_snapshot->>'regra'='diaria_v1'
 AND jsonb_typeof(a.contexto_snapshot->'data_ativacao')='string'
 AND a.contexto_snapshot->>'data_ativacao' ~ '^\d{4}-\d{2}-\d{2}$'
 AND CASE WHEN jsonb_typeof(a.factos_revisoes)='array' THEN
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x WHERE
   (jsonb_typeof(x)='object' AND jsonb_typeof(x->'id')='string' AND x->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND jsonb_typeof(x->'revision')='number' AND x->>'revision' ~ '^[1-9][0-9]*$') IS NOT TRUE)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x GROUP BY x->>'id' HAVING count(*)>1)
 ELSE false END
 AND coalesce(array_ndims(a.pendencias),1)=1 AND array_position(a.pendencias,NULL) IS NULL
 AND NOT EXISTS(SELECT 1 FROM unnest(a.pendencias) x WHERE nullif(btrim(x),'') IS NULL)
 AND cardinality(a.pendencias)=(SELECT count(DISTINCT x) FROM unnest(a.pendencias) x)
 AND CASE WHEN a.referencia_estado='pendente' THEN
  a.expected_minutes IS NULL AND a.horario_snapshot IS NULL
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=0
  AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL AND a.referencia_origem='automatico'
 ELSE
  a.expected_minutes IS NOT NULL AND a.expected_minutes BETWEEN 1 AND 1440
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=3
  AND CASE WHEN jsonb_typeof(a.horario_snapshot)='object' AND jsonb_typeof(a.horario_snapshot->'intervals')='array' THEN
   jsonb_typeof(a.horario_snapshot->'expected_minutes')='number'
   AND a.horario_snapshot->>'expected_minutes'=a.expected_minutes::text
   AND jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.horario_snapshot->'intervals') x WHERE
    (jsonb_typeof(x)='object' AND jsonb_typeof(x->'start')='string' AND jsonb_typeof(x->'end')='string'
     AND x->>'start' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND x->>'end' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     AND x->>'end'>x->>'start') IS NOT TRUE)
  ELSE false END
  AND CASE WHEN a.referencia_origem='automatico' THEN
   num_nonnulls(a.permanencia_id,a.obra_origem_id,a.horario_versao_id)=3
   AND jsonb_typeof(a.permanencia_snapshot)='object'
   AND a.permanencia_snapshot->>'id'=a.permanencia_id::text
   AND a.permanencia_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.permanencia_snapshot->>'colaborador_id'=a.colaborador_id::text
   AND a.permanencia_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.horario_snapshot->>'versao_id'=a.horario_versao_id::text
  ELSE
   a.permanencia_id IS NULL AND a.permanencia_snapshot IS NULL AND a.horario_versao_id IS NULL
   AND jsonb_typeof(a.referencia_evidencia)='object' AND a.referencia_evidencia<>'{}'::jsonb
   AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL
  END
 END
 AND CASE WHEN a.he_estado IN('validada','nao_considerada') THEN
  a.excedente_minutes IS NOT NULL AND a.excedente_minutes>0
  AND num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=4
  AND a.decisao_fingerprint ~ '^[0-9a-f]{64}$' AND nullif(btrim(a.he_motivo),'') IS NOT NULL
 ELSE num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=0 END) AND (
 a.ativa=(a.estado<>'inativa')
 AND CASE WHEN a.referencia_estado='capturada' AND NOT ('intervalo_aberto'=ANY(a.pendencias)) AND NOT ('conflito_factos'=ANY(a.pendencias)) THEN
  num_nonnulls(a.falta_minutes,a.excedente_minutes)=2
  AND a.falta_minutes=greatest(0,a.expected_minutes-a.realizado_minutes)
  AND a.excedente_minutes=greatest(0,a.realizado_minutes-a.expected_minutes)
  AND CASE WHEN a.excedente_minutes>0 THEN a.he_estado IN('pendente','validada','nao_considerada') ELSE a.he_estado='nenhum' END
 ELSE num_nonnulls(a.falta_minutes,a.excedente_minutes)=0 AND a.he_estado='nao_avaliavel' END
 AND ('referencia_diaria_pendente'=ANY(a.pendencias))=(a.referencia_estado='pendente')
 AND ('horas_em_falta'=ANY(a.pendencias))=coalesce(a.falta_minutes>0,false)
 AND ('he_diaria_pendente'=ANY(a.pendencias))=(a.he_estado='pendente')
 AND ('he_validada_aguarda_processamento'=ANY(a.pendencias))=(a.he_estado='validada')
 AND (a.he_estado NOT IN('validada','nao_considerada') OR a.decisao_fingerprint=folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot))
 AND a.estado=CASE WHEN NOT a.ativa THEN 'inativa'
  WHEN a.referencia_estado='pendente' THEN 'referencia_pendente'
  WHEN 'conflito_factos'=ANY(a.pendencias) THEN 'conflito'
  WHEN 'intervalo_aberto'=ANY(a.pendencias) THEN 'intervalo_aberto'
  WHEN a.falta_minutes>0 THEN 'horas_em_falta'
  WHEN a.excedente_minutes>0 AND a.he_estado<>'nao_considerada' THEN 'potencial_he'
  WHEN cardinality(a.pendencias)>0 THEN 'outras_pendencias' ELSE 'regular' END)) IS NOT TRUE;
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'AD14_EXISTING_INVALID_EVALUATIONS: %',bad; END IF;
END $gate$;
CREATE SCHEMA primeline_ad14_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad14_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad14_backup.constraints AS SELECT conname,pg_get_constraintdef(oid) definicao,convalidated FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass;
CREATE TABLE primeline_ad14_backup.ad15 AS SELECT pg_get_functiondef(p.oid) definicao,p.proowner,p.proacl,p.prosecdef,p.proconfig FROM pg_proc p WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure;
CREATE TABLE primeline_ad14_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['folha_avaliacoes_diarias','folha_gestao_historico','folha_registos','folha_he','folha_vencimentos','folha_horarios_versoes','folha_config_empresa'] LOOP
 EXECUTE format('INSERT INTO primeline_ad14_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP; END $snapshot$;
CREATE TABLE primeline_ad14_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad14_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD14_BACKUP_OK' resultado;
COMMIT;
