-- LOCAL ONLY. Requires exact AD-03 baseline. No activation, assignment, monetary effect or data backfill.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_registos,public.folha_he,public.folha_vencimentos,public.folha_gestao_historico,public.folha_horarios,public.folha_horarios_versoes,public.folha_jornadas_individuais_versoes,public.folha_config_empresa,public.ausencias,public.alertas,public.quadro_equipa_permanencias,public.quadro_pessoal_movimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $baseline$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='8b2e36eb831f61ed9b4bb106c65a0851bd8f6ab894214a83d93cac2ccbfbe630' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_recalcular(uuid,date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='5ad0846b9140478670e861d330a30e9a8903a1e047df44ff9a0e48d860f97f49' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: folha_privado.diaria_recalcular(uuid,date,uuid)'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='6ffbdf8c54d4f2ab6d77b087813d9c343fd6bcf280b9cd1bce50fad4aee7497d' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.payroll_facts(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='746f1f317bce21439459396ee0dce04f5871d53391f96e0486fd29bf76ff26ba' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: folha_privado.payroll_facts(uuid,date)'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_gestao_preservada(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='40056038d5203d8906f1004504fd14462fb79c62ad373db883fc771f20af261b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: folha_privado.diaria_gestao_preservada(text,jsonb,boolean,text)'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_gestao_v2(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='8b1cede8f9e3ca43abefa5718e6a01cce63aad37cf16bec63c0873e74571806d' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(proacl) v)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'HR27_FUNCTION_DRIFT: public.fn_folha_gestao_v2(text,jsonb,boolean,text)'; END IF;
END $baseline$;
DO $hours_dependencies$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.ator()') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='176c4fb030401fb45c89f3cd1616a9d26e9e15b691ff524a33dfc8d233c6b079' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.ator()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.obra(uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='731f5289cd29bdb7f7d69723fabb76cbb8b8e577bb474c679f991c7271d9788e' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.obra(uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.lock_dia(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='b29022304f316e25dd34bae7a1e1906a0dfd72bd041a1d658338cc8394745502' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.lock_dia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.local(uuid,uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9eb2f0d8b7e52d5280f0798c48cb8ec84377281c1e13706bc066b1cf3765070b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.local(uuid,uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_contexto_v2(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5ca6e224708a655a9c778fa6a5701b39e6c0aab8dbf0a01a87ffb77d42ea095' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner AND x.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: public.fn_folha_contexto_v2(date,uuid)';END IF;
END $hours_dependencies$;DO $guard$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
IF to_regclass('public.folha_jornadas_individuais_versoes') IS NULL THEN RAISE EXCEPTION 'HR27_REQUIRES_AD03';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred) THEN RAISE EXCEPTION 'HR27_AD14_TRIGGER_DRIFT';END IF;
IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE folha_privado.diaria_ad14_valida(a,true) IS NOT TRUE OR folha_privado.jornada_ad03_avaliacao_valida(a) IS NOT TRUE) THEN RAISE EXCEPTION 'HR27_INVALID_EXISTING_EVALUATION';END IF;
END $guard$;
DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_hr27_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_hr27_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE n.nspname='primeline_hr27_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_hr27_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'HR27_BACKUP_NOT_PRIVATE'; END IF;
FOR r IN SELECT * FROM primeline_hr27_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'HR27_DATA_DRIFT: %',r.tabela;END IF;END LOOP;
END $data$;
DO $constraints$ DECLARE n text;BEGIN SELECT conname INTO STRICT n FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%NOT ativa%' AND pg_get_constraintdef(oid) LIKE '%he_validada_aguarda_processamento%';EXECUTE format('ALTER TABLE public.folha_avaliacoes_diarias DROP CONSTRAINT %I',n);END $constraints$;
CREATE OR REPLACE FUNCTION folha_privado.diaria_ad14_valida(r public.folha_avaliacoes_diarias,p_final boolean) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $validator$
 SELECT ((
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
  a.expected_minutes IS NOT NULL AND a.expected_minutes BETWEEN 0 AND 1440
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=3
  AND CASE WHEN jsonb_typeof(a.horario_snapshot)='object' AND jsonb_typeof(a.horario_snapshot->'intervals')='array' THEN
   jsonb_typeof(a.horario_snapshot->'expected_minutes')='number'
   AND a.horario_snapshot->>'expected_minutes'=a.expected_minutes::text
   AND (jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16 OR (a.expected_minutes=0 AND a.horario_snapshot->>'day_type'='folga' AND a.horario_snapshot->'intervals'='[]'::jsonb))
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
 ELSE num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=0 END) AND (NOT p_final OR (
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
 AND (NOT ('he_validada_aguarda_processamento'=ANY(a.pendencias)) OR a.he_estado='validada')
 AND (a.he_estado NOT IN('validada','nao_considerada') OR a.decisao_fingerprint=folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot))
 AND a.estado=CASE WHEN NOT a.ativa THEN 'inativa'
  WHEN a.referencia_estado='pendente' THEN 'referencia_pendente'
  WHEN 'conflito_factos'=ANY(a.pendencias) THEN 'conflito'
  WHEN 'intervalo_aberto'=ANY(a.pendencias) THEN 'intervalo_aberto'
  WHEN a.falta_minutes>0 THEN 'horas_em_falta'
  WHEN a.excedente_minutes>0 AND (a.he_estado NOT IN('validada','nao_considerada') OR 'he_validada_aguarda_processamento'=ANY(a.pendencias)) THEN 'potencial_he'
  WHEN cardinality(a.pendencias)>0 THEN 'outras_pendencias' ELSE 'regular' END))) IS TRUE FROM (SELECT (r).*) a
$validator$;

CREATE OR REPLACE FUNCTION folha_privado.diaria_recalcular(p uuid,d date,req uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; old public.folha_avaliacoes_diarias; n public.folha_avaliacoes_diarias; f jsonb; ref jsonb; hash text; decision text; pend text[]:='{}'; action text; personal boolean;
BEGIN
 u:=folha_privado.ator();PERFORM folha_privado.lock_dia(p,d);
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT'; END IF;
 SELECT * INTO old FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
 personal:=folha_privado.diaria_pessoal(p,d);
 IF NOT personal AND old.id IS NULL THEN RETURN NULL; END IF;
 f:=folha_privado.diaria_factos(p,d); hash:=encode(sha256(convert_to((f->'canonical')::text,'UTF8')),'hex');
 IF old.id IS NOT NULL AND old.factos_fingerprint=hash AND old.ativa=personal THEN RETURN to_jsonb(old); END IF;
 n:=old;
 IF old.id IS NULL THEN
  ref:=folha_privado.diaria_referencia(p,d);
  n.id:=gen_random_uuid();n.empresa_id:=u.empresa_id;n.colaborador_id:=p;n.data:=d;n.referencia_revision:=1;
  n.referencia_estado:=ref->>'referencia_estado';n.referencia_origem:=ref->>'referencia_origem';n.jornada_versao_id:=(ref->>'jornada_versao_id')::uuid;n.permanencia_id:=(ref->>'permanencia_id')::uuid;n.obra_origem_id:=(ref->>'obra_origem_id')::uuid;n.horario_versao_id:=(ref->>'horario_versao_id')::uuid;
  n.permanencia_snapshot:=nullif(ref->'permanencia_snapshot','null'::jsonb);n.horario_snapshot:=nullif(ref->'horario_snapshot','null'::jsonb);n.contexto_snapshot:=ref->'contexto_snapshot';
  n.expected_minutes:=(ref->>'expected_minutes')::integer;n.referencia_motivo:=ref->>'referencia_motivo';n.referencia_evidencia:=ref->'referencia_evidencia';
  IF n.referencia_estado='capturada' THEN n.capturado_por:=u.id;n.capturado_em:=now();n.captura_request_id:=req; END IF;
  n.criado_por:=u.id;n.criado_em:=now();n.request_id_inicial:=req;n.he_estado:='nenhum';
 END IF;
 n.ativa:=personal;n.modo_dia:=CASE WHEN (f->>'mixed')::boolean THEN 'misto' ELSE 'personalizado' END;n.revision:=coalesce(old.revision,0)+1;
 n.realizado_minutes:=(f->>'minutes')::integer;n.factos_fingerprint:=hash;n.factos_revisoes:=f->'revisions';n.fingerprint_version:='folha_factos_v1';n.regra_avaliacao_version:='diaria_v1';
 n.atualizado_por:=u.id;n.avaliado_por:=u.id;n.atualizado_em:=now();n.avaliado_em:=now();n.ultimo_request_id:=req;
 decision:=folha_privado.diaria_decisao_hash(hash,n.referencia_revision,n.horario_snapshot);
 IF old.he_estado IN('validada','nao_considerada') AND old.decisao_fingerprint IS DISTINCT FROM decision THEN
  INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason) VALUES(u.empresa_id,'daily_he_invalidate',n.id,to_jsonb(old),jsonb_build_object('facts',hash),u.id,req,'Factos/referência alterados');
  n.he_estado:='nenhum';n.decisao_fingerprint:=NULL;n.he_decidido_por:=NULL;n.he_decidido_em:=NULL;n.he_motivo:=NULL;
 END IF;
 n.falta_minutes:=NULL;n.excedente_minutes:=NULL;
 IF n.referencia_estado='pendente' THEN pend:=array_append(pend,'referencia_diaria_pendente'); END IF;
 IF (f->>'open')::boolean THEN pend:=array_append(pend,'intervalo_aberto'); END IF;
 IF (f->>'conflict')::boolean THEN pend:=array_append(pend,'conflito_factos'); END IF;
 IF (f->>'special_pending')::boolean THEN pend:=array_append(pend,'dia_especial_pendente'); END IF;
 IF n.expected_minutes IS NOT NULL AND NOT (f->>'open')::boolean AND NOT (f->>'conflict')::boolean THEN
  n.falta_minutes:=greatest(0,n.expected_minutes-n.realizado_minutes);n.excedente_minutes:=greatest(0,n.realizado_minutes-n.expected_minutes);
  IF n.falta_minutes>0 THEN pend:=array_append(pend,'horas_em_falta'); END IF;
  IF n.excedente_minutes>0 THEN
   IF n.he_estado NOT IN('validada','nao_considerada') THEN n.he_estado:='pendente'; END IF;
   IF n.he_estado='pendente' THEN pend:=array_append(pend,'he_diaria_pendente'); END IF;
  ELSE n.he_estado:='nenhum'; END IF;
 ELSE n.he_estado:='nao_avaliavel'; END IF;
 IF n.he_estado NOT IN('validada','nao_considerada') THEN n.decisao_fingerprint:=NULL;n.he_decidido_por:=NULL;n.he_decidido_em:=NULL;n.he_motivo:=NULL; END IF;
 n.pendencias:=pend;
 n.estado:=CASE WHEN NOT personal THEN 'inativa' WHEN n.referencia_estado='pendente' THEN 'referencia_pendente' WHEN (f->>'conflict')::boolean THEN 'conflito' WHEN (f->>'open')::boolean THEN 'intervalo_aberto' WHEN n.falta_minutes>0 THEN 'horas_em_falta' WHEN n.excedente_minutes>0 AND n.he_estado NOT IN('validada','nao_considerada') THEN 'potencial_he' WHEN cardinality(pend)>0 THEN 'outras_pendencias' ELSE 'regular' END;
 action:=CASE WHEN old.id IS NULL THEN 'daily_evaluation_create' WHEN NOT personal THEN 'daily_evaluation_deactivate' WHEN NOT old.ativa THEN 'daily_evaluation_reactivate' ELSE 'daily_evaluation_recalculate' END;
 IF old.id IS NULL THEN INSERT INTO public.folha_avaliacoes_diarias SELECT (n).*;
 ELSE UPDATE public.folha_avaliacoes_diarias SET (ativa,modo_dia,revision,realizado_minutes,falta_minutes,excedente_minutes,estado,he_estado,pendencias,factos_revisoes,factos_fingerprint,decisao_fingerprint,he_decidido_por,he_decidido_em,he_motivo,atualizado_por,atualizado_em,avaliado_por,avaliado_em,ultimo_request_id) =
 (n.ativa,n.modo_dia,n.revision,n.realizado_minutes,n.falta_minutes,n.excedente_minutes,n.estado,n.he_estado,n.pendencias,n.factos_revisoes,n.factos_fingerprint,n.decisao_fingerprint,n.he_decidido_por,n.he_decidido_em,n.he_motivo,n.atualizado_por,n.atualizado_em,n.avaliado_por,n.avaliado_em,n.ultimo_request_id) WHERE id=n.id; END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id) VALUES(u.empresa_id,action,n.id,CASE WHEN old.id IS NOT NULL THEN to_jsonb(old) END,to_jsonb(n),u.id,req);
 RETURN to_jsonb(n);
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_diaria_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; cfg public.folha_config_empresa; a public.folha_avaliacoes_diarias; v public.folha_horarios_versoes; h public.folha_horarios;
 req uuid:=(p_dados->>'request_id')::uuid; p uuid:=(p_dados->>'person_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date; before jsonb; after jsonb; payload jsonb; token text; result jsonb; op folha_privado.operacoes; schedule_row record; rev integer; next_rev integer; expected integer; reason text:=nullif(btrim(p_dados->>'reason'),''); facts jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 -- Formal templates are serialized before preview/snapshot; actual fact clocks are unchanged.
 LOCK TABLE public.folha_horarios IN SHARE ROW EXCLUSIVE MODE;
 u:=folha_privado.ator();SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo IS TRUE FOR SHARE;IF u.id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;IF NOT folha_privado.admin() THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao<>'configure_schedule' AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo/Gestão' USING ERRCODE='42501'; END IF;
 -- AD-15: session actor is the only tenant authority; revalidate before replay.
 IF u.empresa_id IS NULL OR (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'DAILY_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 IF p_acao IN('daily_activation','daily_he_validate','daily_he_disregard') AND w IS NOT NULL THEN RAISE EXCEPTION 'DAILY_GLOBAL_WORK_CONTEXT_FORBIDDEN' USING ERRCODE='42501'; END IF;
 IF p IS NOT NULL THEN
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
 END IF;
 IF w IS NOT NULL THEN
  PERFORM 1 FROM public.obras o WHERE o.id=w AND o.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_WORK_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 END IF;
 IF p_acao IN('daily_reference_correct','daily_he_validate','daily_he_disregard') THEN
  PERFORM folha_privado.lock_dia(p,d);
  SELECT * INTO a FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
  IF a.id IS NULL OR (p_dados ? 'evaluation_id' AND (p_dados->>'evaluation_id')::uuid IS DISTINCT FROM a.id) THEN RAISE EXCEPTION 'DAILY_EVALUATION_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  IF a.obra_origem_id IS NOT NULL THEN
   PERFORM 1 FROM public.obras o WHERE o.id=a.obra_origem_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_REFERENCE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  END IF;
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF (p_dados->>'version')::integer IS DISTINCT FROM 2 OR req IS NULL OR p_confirmar IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato diário'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;RETURN op.resultado;
 END IF;
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id FOR UPDATE;
 IF cfg.empresa_id IS NULL AND p_acao<>'configure_schedule' THEN RAISE EXCEPTION 'COMPANY_CONFIGURATION_REQUIRED'; END IF;
 IF p_acao='daily_activation' THEN
  IF cfg.avaliacao_diaria_data_ativacao IS NOT NULL THEN RAISE EXCEPTION 'DAILY_ALREADY_ACTIVATED'; END IF;
  IF d IS DISTINCT FROM today THEN RAISE EXCEPTION 'ACTIVATION_MUST_BE_TODAY'; END IF;
  -- Validate/lock the real schedule-work references, without changing hours.
  FOR schedule_row IN SELECT s.obra_id FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id ORDER BY s.obra_id FOR SHARE LOOP
   PERFORM 1 FROM public.obras o WHERE o.id=schedule_row.obra_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
   PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',configured.intervals,'expected_minutes',configured.expected_minutes),true) FROM public.folha_horarios configured WHERE configured.obra_id=schedule_row.obra_id AND configured.empresa_id=u.empresa_id;
  END LOOP;
  rev:=cfg.revision;before:=to_jsonb(cfg);
  after:=jsonb_build_object('activation_date',today,'schedules',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.obra_id),'[]') FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id));
 ELSIF p_acao IN('configure_schedule','schedule_retro_correct') THEN
  PERFORM folha_privado.obra(w,true);SELECT * INTO h FROM public.folha_horarios WHERE obra_id=w FOR UPDATE;
  IF h.obra_id IS NOT NULL AND h.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  IF p_acao='configure_schedule' THEN
   IF p_dados ? 'vigente_desde' AND (p_dados->>'vigente_desde')::date IS DISTINCT FROM today THEN RAISE EXCEPTION 'SCHEDULE_EFFECTIVE_TODAY_ONLY'; END IF;
   d:=today;before:=to_jsonb(h);rev:=coalesce(h.revision,0);
   SELECT * INTO v FROM public.folha_horarios_versoes WHERE obra_id=w AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d) FOR UPDATE;
  ELSE
   d:=(p_dados->>'vigente_desde')::date;
   IF d IS NULL OR d>=today OR d<cfg.avaliacao_diaria_data_ativacao OR cfg.avaliacao_diaria_data_ativacao IS NULL OR reason IS NULL THEN RAISE EXCEPTION 'RETRO_SCHEDULE_REASON_AND_VALID_DATE_REQUIRED'; END IF;
   SELECT * INTO v FROM public.folha_horarios_versoes WHERE id=(p_dados->>'version_id')::uuid AND obra_id=w AND empresa_id=u.empresa_id AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d) FOR UPDATE;
   IF v.id IS NULL THEN RAISE EXCEPTION 'SCHEDULE_VERSION_NOT_FOUND'; END IF;
   rev:=v.revision;before:=to_jsonb(v);
  END IF;
  facts:=folha_privado.horario_ad13_factos(p_dados,true);
  IF (facts->>'open')::boolean OR (p_dados->>'expected_minutes')::integer IS DISTINCT FROM (facts->>'minutes')::integer OR jsonb_array_length(p_dados->'intervals')<>2 OR (SELECT count(DISTINCT x->>'period') FROM jsonb_array_elements(p_dados->'intervals') x WHERE x->>'period' IN('manha','tarde'))<>2 THEN RAISE EXCEPTION 'SCHEDULE_INVALID'; END IF;
  expected:=(p_dados->>'expected_minutes')::integer;
  next_rev:=greatest(coalesce(h.revision,0),coalesce((SELECT max(revision) FROM public.folha_horarios_versoes WHERE obra_id=w),0))+1;
  after:=jsonb_build_object('intervals',p_dados->'intervals','expected_minutes',(p_dados->>'expected_minutes')::integer,'vigente_desde',d,'revision',CASE WHEN p_acao='configure_schedule' THEN rev+1 ELSE next_rev END,'version_revision',next_rev,'previous_version',to_jsonb(v),'affected_evaluations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.data,'revision',e.revision) ORDER BY e.data,e.id),'[]') FROM public.folha_avaliacoes_diarias e WHERE e.empresa_id=u.empresa_id AND e.obra_origem_id=w AND e.data>=d AND (v.vigente_ate IS NULL OR e.data<v.vigente_ate)));
 ELSE
  IF p_acao NOT IN('daily_reference_correct','daily_he_validate','daily_he_disregard') THEN RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
  PERFORM folha_privado.lock_dia(p,d);
  SELECT * INTO a FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
  IF a.id IS NULL OR NOT a.ativa THEN RAISE EXCEPTION 'DAILY_EVALUATION_NOT_ACTIVE'; END IF;
  IF EXISTS(SELECT 1 FROM public.folha_vencimentos WHERE colaborador_id=p AND competencia=date_trunc('month',d)::date AND estado IN('closed','exported')) THEN RAISE EXCEPTION 'PAYROLL_CLOSED_FACTS_CHANGED'; END IF;
  facts:=folha_privado.diaria_factos(p,d);
  IF a.factos_fingerprint IS DISTINCT FROM encode(sha256(convert_to((facts->'canonical')::text,'UTF8')),'hex') THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  rev:=a.revision;before:=to_jsonb(a);
  IF reason IS NULL OR length(reason)>1000 THEN RAISE EXCEPTION 'ADMIN_REASON_REQUIRED'; END IF;
  IF p_acao='daily_reference_correct' THEN
   facts:=folha_privado.horario_ad13_factos(p_dados->'schedule',false);
   expected:=(p_dados->'schedule'->>'expected_minutes')::integer;
   IF (facts->>'open')::boolean OR expected IS DISTINCT FROM (facts->>'minutes')::integer OR expected NOT BETWEEN 0 AND 1440 OR jsonb_typeof(p_dados->'evidence') IS DISTINCT FROM 'object' OR p_dados->'evidence'='{}'::jsonb THEN RAISE EXCEPTION 'REFERENCE_EVIDENCE_REQUIRED'; END IF;
   IF w IS NOT NULL THEN PERFORM folha_privado.obra(w); END IF;
   after:=jsonb_build_object('schedule',p_dados->'schedule','evidence',p_dados->'evidence','reason',reason,'work_id',w);
  ELSE
   IF a.excedente_minutes IS NULL OR a.excedente_minutes<=0 OR a.he_estado NOT IN('pendente','validada','nao_considerada') THEN RAISE EXCEPTION 'DAILY_HE_NOT_EVALUABLE'; END IF;
   after:=jsonb_build_object('he_estado',CASE p_acao WHEN 'daily_he_validate' THEN 'validada' ELSE 'nao_considerada' END,'reason',reason,'minutes',a.excedente_minutes,'fingerprint',folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot),'he_policy','HR-27','financial_effect',false);
  END IF;
 END IF;
 IF (p_dados->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 token:=encode(sha256(convert_to(jsonb_build_array(payload,before,after,to_jsonb(cfg))::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='daily_activation' THEN
  UPDATE public.folha_config_empresa SET avaliacao_diaria_data_ativacao=today,avaliacao_diaria_ativada_em=now(),avaliacao_diaria_ativada_por=u.id,avaliacao_diaria_ativacao_request_id=req,revision=revision+1 WHERE empresa_id=u.empresa_id;
  FOR schedule_row IN SELECT * FROM public.folha_horarios WHERE empresa_id=u.empresa_id ORDER BY obra_id LOOP
   PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',schedule_row.intervals,'expected_minutes',schedule_row.expected_minutes),true);
   INSERT INTO public.folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,criado_por,request_id) VALUES(u.empresa_id,schedule_row.obra_id,schedule_row.revision,jsonb_build_object('intervals',schedule_row.intervals,'expected_minutes',schedule_row.expected_minutes),today,u.id,req);
  END LOOP;
 ELSIF p_acao IN('configure_schedule','schedule_retro_correct') THEN
  IF cfg.avaliacao_diaria_data_ativacao IS NOT NULL THEN
   IF v.id IS NOT NULL THEN UPDATE public.folha_horarios_versoes SET vigente_ate=d WHERE id=v.id; END IF;
   INSERT INTO public.folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,vigente_ate,criado_por,request_id,motivo) VALUES(u.empresa_id,w,next_rev,jsonb_build_object('intervals',after->'intervals','expected_minutes',expected),d,CASE WHEN p_acao='schedule_retro_correct' THEN v.vigente_ate END,u.id,req,reason);
  END IF;
  IF p_acao='configure_schedule' OR v.vigente_ate IS NULL THEN
   INSERT INTO public.folha_horarios(obra_id,empresa_id,intervals,expected_minutes,revision) VALUES(w,u.empresa_id,after->'intervals',(after->>'expected_minutes')::integer,coalesce(h.revision,0)+1)
   ON CONFLICT(obra_id) DO UPDATE SET intervals=excluded.intervals,expected_minutes=excluded.expected_minutes,revision=excluded.revision;
  END IF;
 ELSIF p_acao='daily_reference_correct' THEN
  IF a.he_estado IN('validada','nao_considerada') THEN
   INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
   VALUES(u.empresa_id,'daily_he_invalidate',a.id,to_jsonb(a),jsonb_build_object('reason','Referência administrativa alterada'),u.id,req,reason);
  END IF;
  UPDATE public.folha_avaliacoes_diarias SET referencia_estado='capturada',referencia_origem='administrativo',jornada_versao_id=NULL,referencia_revision=referencia_revision+1,falta_minutes=NULL,excedente_minutes=NULL,he_estado='nao_avaliavel',decisao_fingerprint=NULL,he_decidido_por=NULL,he_decidido_em=NULL,he_motivo=NULL,pendencias=array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'),permanencia_id=NULL,permanencia_snapshot=NULL,obra_origem_id=w,horario_versao_id=NULL,horario_snapshot=p_dados->'schedule',expected_minutes=expected,referencia_motivo=reason,referencia_evidencia=p_dados->'evidence',capturado_por=u.id,capturado_em=now(),captura_request_id=req,factos_fingerprint=repeat('0',64),atualizado_por=u.id,atualizado_em=now(),ultimo_request_id=req WHERE id=a.id;
  after:=folha_privado.diaria_recalcular(p,d,req);
 ELSE
  UPDATE public.folha_avaliacoes_diarias SET he_estado=after->>'he_estado',he_motivo=reason,he_decidido_por=u.id,he_decidido_em=now(),decisao_fingerprint=after->>'fingerprint',revision=revision+1,atualizado_por=u.id,atualizado_em=now(),ultimo_request_id=req,
   pendencias=array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'),
   estado=CASE WHEN cardinality(array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'))>0 THEN 'outras_pendencias' ELSE 'regular' END WHERE id=a.id;
  SELECT to_jsonb(x) INTO after FROM public.folha_avaliacoes_diarias x WHERE id=a.id;
 END IF;
 IF p_acao IN('daily_he_validate','daily_he_disregard') THEN after:=after||jsonb_build_object('he_policy','HR-27','financial_effect',false); END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,reason) VALUES(u.empresa_id,w,p_acao,coalesce(a.id,v.id,w,u.empresa_id),before,after,u.id,req,reason);
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',coalesce((after->>'revision')::integer,rev+1),'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $$;

CREATE OR REPLACE FUNCTION folha_privado.payroll_facts(p uuid,m date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'minutes',f.minutes,'state',coalesce((SELECT CASE WHEN cardinality(array_remove(a.pendencias,'he_validada_aguarda_processamento'))=0 AND a.referencia_estado='capturada' AND a.falta_minutes=0 AND a.excedente_minutes IS NOT NULL AND a.he_estado IN('nenhum','validada','nao_considerada') THEN 'registered' ELSE 'regularization' END FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=f.data AND a.ativa),f.estado),'special_day',f.special_day,'special_reviewed',f.special_reviewed_at IS NOT NULL) ORDER BY f.data,f.id)
 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data>=m AND f.data<(m+interval '1 month')::date),'[]'),
 'absences',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'type',a.tipo,'state',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date),'[]'),
 'pending_days',coalesce((SELECT jsonb_agg(data ORDER BY data) FROM (SELECT DISTINCT q.data FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=m AND q.data<(m+interval '1 month')::date AND q.data<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=q.data AND a.ativa) AND NOT EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=q.data AND f.obra_id IS NOT DISTINCT FROM q.obra_id) AND NOT EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=q.data) AND NOT EXISTS(SELECT 1 FROM public.ponto_pessoal_obra h WHERE h.colaborador_id=p AND h.data=q.data)) missing),'[]'),
 'legacy_days',coalesce((SELECT jsonb_agg(DISTINCT data ORDER BY data) FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data>=m AND data<(m+interval '1 month')::date),'[]'),
 'financial_effect',false,'legacy_not_converted',true)
 || CASE WHEN EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date AND a.ativa) THEN
 jsonb_build_object('daily_evaluations',(SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'revision',a.revision,'reference_revision',a.referencia_revision,'fingerprint',a.factos_fingerprint,'state',a.estado,'expected_minutes',a.expected_minutes,'minutes',a.realizado_minutes,'he_state',a.he_estado,'pending',a.pendencias) ORDER BY a.data,a.id) FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date AND a.ativa)) ELSE '{}'::jsonb END
$$;

CREATE OR REPLACE FUNCTION folha_privado.diaria_gestao_preservada(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; req uuid:=(p_dados->>'request_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid;
 person uuid:=(p_dados->>'person_id')::uuid; entity uuid; before jsonb; after jsonb; payload jsonb; op folha_privado.operacoes; previous_request text;
 token text; result jsonb; expected integer; rev integer; d date; m date; dates date[]; scope_dates date[]; a date; item jsonb;
 h public.folha_he; f public.folha_registos; v public.folha_vencimentos; t public.folha_tarefas_reportes; task public.planeamento_itens;
 cfg public.folha_config_empresa; ab public.ausencias; facts jsonb; pending boolean; consumed integer:=0; histids jsonb;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao IN('payroll_validate','payroll_close','payroll_reopen','he_validate','he_process','configure_he_eligibility','absence_confirm','special_review') AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo' USING ERRCODE='42501'; END IF;
 IF p_acao IN('configure_company','configure_schedule','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','configure_he_eligibility','absence_confirm','special_review') AND NOT folha_privado.admin()
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao IN('configure_company','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','configure_he_eligibility','absence_confirm','special_review') AND w IS NOT NULL THEN
  RAISE EXCEPTION 'ADMIN_WORK_SCOPE_INVALID: ação administrativa sem obra' USING ERRCODE='22023';
 END IF;
 IF p_acao='configure_schedule' THEN PERFORM folha_privado.obra(w); END IF;
 -- Replays must obey the actor's CURRENT role and work scope.
 IF p_acao IN('task_report','task_confirm') THEN
  PERFORM folha_privado.obra(w);
  IF p_acao='task_report' AND (u.funcao<>'encarregado' AND NOT folha_privado.superuser()) OR p_acao='task_confirm' AND (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501';
  END IF;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
  IF NOT FOUND OR p_acao IN('he_approve','he_reject') AND (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR p_acao='he_validate' AND NOT folha_privado.admin() THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501';
  END IF;
  PERFORM folha_privado.obra(h.obra_id);
 END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados,'contract','gestao_v2');
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  -- Recheck entity tenant/scope without revisiting completed transition/revision.
  IF person IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  IF p_acao='he_process' THEN
   SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501'; END IF;
   PERFORM folha_privado.obra(h.obra_id);
  ELSIF p_acao='special_review' THEN
   SELECT * INTO f FROM public.folha_registos WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: Folha' USING ERRCODE='42501'; END IF;
  ELSIF p_acao='absence_confirm' AND NOT EXISTS(SELECT 1 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=(p_dados->>'id')::uuid AND c.empresa_id=u.empresa_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501';
  ELSIF p_acao IN('task_report','task_confirm') AND NOT EXISTS(SELECT 1 FROM public.planeamento_itens pi JOIN public.fases fase ON fase.id=pi.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE pi.id=(p_dados->>'task_id')::uuid AND fase.obra_id=w AND o.empresa_id=u.empresa_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501';
  END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 expected:=(p_dados->>'expected_revision')::integer;
 IF p_acao='configure_he_eligibility' THEN
  before:=to_jsonb(cfg);entity:=u.empresa_id;rev:=coalesce(cfg.revision,0);
  IF jsonb_typeof(p_dados->'roles') IS DISTINCT FROM 'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'roles') x WHERE jsonb_typeof(x)<>'string' OR length(btrim(x#>>'{}')) NOT BETWEEN 1 AND 100) THEN RAISE EXCEPTION 'HE_ELIGIBILITY_INVALID'; END IF;
  after:=jsonb_build_object('roles',(SELECT coalesce(jsonb_agg(DISTINCT lower(btrim(x))),'[]') FROM jsonb_array_elements_text(p_dados->'roles') x));
 ELSIF p_acao='absence_confirm' THEN
  SELECT a.* INTO ab FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=(p_dados->>'id')::uuid AND c.empresa_id=u.empresa_id FOR UPDATE OF a;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501'; END IF;
  IF ab.estado<>'ausente_pendente' THEN RAISE EXCEPTION 'ABSENCE_TRANSITION_INVALID'; END IF;
  IF ab.tipo='baixa_doenca' AND NOT EXISTS(SELECT 1 FROM public.ausencias_anexos WHERE ausencia_id=ab.id AND nullif(btrim(arquivo_url),'') IS NOT NULL) THEN RAISE EXCEPTION 'DOCUMENTO_PENDENTE'; END IF;
  entity:=ab.id;before:=to_jsonb(ab);rev:=0;
  IF p_dados->>'expected_state' IS DISTINCT FROM ab.estado OR p_dados->>'expected_type' IS DISTINCT FROM ab.tipo THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  after:=jsonb_build_object('estado',CASE WHEN ab.tipo IN('baixa_doenca','baixa_maternidade','baixa_parental','falta_justificada_com_remuneracao') THEN 'confirmada' ELSE 'justificada' END);
  IF nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'ABSENCE_REASON_REQUIRED'; END IF;
 ELSIF p_acao='special_review' THEN
  SELECT * INTO f FROM public.folha_registos WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND OR NOT f.special_day THEN RAISE EXCEPTION 'SPECIAL_REVIEW_INVALID'; END IF;
  entity:=f.id;before:=to_jsonb(f);rev:=f.revision;after:=jsonb_build_object('reviewed',true);
 ELSIF p_acao='he_process' THEN
  SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND OR h.estado<>'validated_pending_rule' OR h.processado_em IS NOT NULL THEN RAISE EXCEPTION 'HE_PROCESS_INVALID'; END IF;
  SELECT * INTO f FROM public.folha_registos WHERE id=h.folha_id FOR SHARE;
  IF f.revision<>h.folha_revision THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  entity:=h.id;w:=h.obra_id;before:=to_jsonb(h);rev:=h.revision;after:=jsonb_build_object('processado',true,'financial_effect',false);
 ELSIF p_acao='configure_company' THEN
  before:=to_jsonb(cfg); entity:=u.empresa_id; rev:=coalesce(cfg.revision,0);
  IF p_dados ? 'correction_days' AND (p_dados->>'correction_days')::integer IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'VALIDATION_ERROR: janela'; END IF;
  IF p_dados ? 'office_expected_minutes' AND coalesce((p_dados->>'office_expected_minutes')::integer,0) NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'VALIDATION_ERROR: carga escritório'; END IF;
  after:=jsonb_build_object('office_expected_minutes',coalesce((p_dados->>'office_expected_minutes')::integer,cfg.office_expected_minutes,480),'correction_days',1,'overtime_enabled',coalesce((p_dados->>'overtime_enabled')::boolean,false),
    'calendar_complete',coalesce((p_dados->>'calendar_complete')::boolean,false),'holiday_dates',coalesce(p_dados->'holiday_dates','[]'),'calendar_validated_years',coalesce(p_dados->'calendar_validated_years',to_jsonb(cfg.calendar_validated_years),'[]'),
    'payroll_rules_ready',coalesce((p_dados->>'payroll_rules_ready')::boolean,false),'official_template_hash',p_dados->>'official_template_hash');
  IF after->>'official_template_hash' IS NOT NULL AND after->>'official_template_hash' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'VALIDATION_ERROR: hash'; END IF;
 ELSIF p_acao='configure_schedule' THEN
  PERFORM folha_privado.obra(w); entity:=w;
  SELECT to_jsonb(x),x.revision INTO before,rev FROM public.folha_horarios x WHERE obra_id=w FOR UPDATE;rev:=coalesce(rev,0);
  facts:=folha_privado.facts(p_dados->'intervals',least((now() AT TIME ZONE 'Europe/Lisbon')::date-1,'2026-01-01'::date));
  IF (facts->>'open')::boolean OR (p_dados->>'expected_minutes')::integer IS NULL OR (p_dados->>'expected_minutes')::integer<>(facts->>'minutes')::integer
   OR jsonb_array_length(p_dados->'intervals')<>2
   OR (SELECT count(DISTINCT x->>'period') FROM jsonb_array_elements(p_dados->'intervals') x WHERE x->>'period' IN('manha','tarde'))<>2
  THEN RAISE EXCEPTION 'SCHEDULE_INVALID'; END IF;
  after:=jsonb_build_object('intervals',p_dados->'intervals','expected_minutes',(p_dados->>'expected_minutes')::integer);
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  entity:=(p_dados->>'id')::uuid;
  SELECT * INTO h FROM public.folha_he WHERE id=entity AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501'; END IF;
  w:=h.obra_id; PERFORM folha_privado.obra(w); SELECT * INTO f FROM public.folha_registos WHERE id=h.folha_id;
  IF p_acao<>'he_reject' THEN
   PERFORM 1 FROM public.colaboradores c WHERE c.id=f.colaborador_id AND c.empresa_id=u.empresa_id AND lower(btrim(c.funcao))=ANY(coalesce(cfg.he_eligible_roles,ARRAY['pedreiro','servente'])) FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'HE_ROLE_NOT_ELIGIBLE'; END IF;
  END IF;
  IF f.revision<>h.folha_revision THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  IF (p_acao IN('he_approve','he_reject') AND ((u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR h.estado<>'potential'))
    OR (p_acao='he_validate' AND (NOT folha_privado.admin() OR h.estado<>'pending_validation'))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: transição HE' USING ERRCODE='42501'; END IF;
  before:=to_jsonb(h);rev:=h.revision;after:=jsonb_build_object('estado',CASE p_acao WHEN 'he_approve' THEN 'pending_validation' WHEN 'he_reject' THEN 'rejected' ELSE 'validated_pending_rule' END);
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace','vacation_entitlement') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  entity:=person;PERFORM folha_privado.lock_dia(person,(now() AT TIME ZONE 'Europe/Lisbon')::date);
  IF p_acao='vacation_entitlement' THEN
   IF (p_dados->>'days')::numeric IS NULL OR (p_dados->>'year')::integer IS NULL OR (p_dados->>'year')::integer NOT BETWEEN 2000 AND 2200
   OR EXISTS(SELECT 1 FROM jsonb_each(p_dados) x WHERE x.key IN('days','carry','additional') AND (jsonb_typeof(x.value)<>'number' OR (x.value#>>'{}')::numeric<>trunc((x.value#>>'{}')::numeric))) THEN RAISE EXCEPTION 'ENTITLEMENT_FULL_DAYS_REQUIRED'; END IF;
   SELECT to_jsonb(x),revision INTO before,rev FROM public.folha_direitos_ferias x WHERE colaborador_id=person AND ano=(p_dados->>'year')::integer FOR UPDATE;
   rev:=coalesce(rev,0);after:=jsonb_build_object('year',(p_dados->>'year')::integer,'days',(p_dados->>'days')::numeric,'source',p_dados->>'source');
   after:=after||jsonb_build_object('carry',coalesce((p_dados->>'carry')::integer,0),'additional',coalesce((p_dados->>'additional')::integer,0),'authorization',p_dados->>'authorization','carry_expires',make_date((p_dados->>'year')::integer,4,30));
   IF (after->>'days')::numeric<>trunc((after->>'days')::numeric) OR (after->>'carry')::integer<0 OR (after->>'additional')::integer<0 OR ((after->>'carry')::integer>0 OR (after->>'additional')::integer>0) AND nullif(btrim(after->>'authorization'),'') IS NULL THEN RAISE EXCEPTION 'ENTITLEMENT_ADJUSTMENT_INVALID'; END IF;
   IF after->>'source' IS NULL OR btrim(after->>'source')='' OR (after->>'days')::numeric<0 THEN RAISE EXCEPTION 'ENTITLEMENT_SOURCE_REQUIRED'; END IF;
  ELSE
   SELECT revision INTO rev FROM public.folha_ferias_revisoes WHERE colaborador_id=person FOR UPDATE;rev:=coalesce(rev,0);
   SELECT ARRAY(SELECT DISTINCT x::date FROM jsonb_array_elements_text(coalesce(p_dados->'dates','[]')) x ORDER BY x::date) INTO dates;
   IF p_dados ? 'from' THEN
    IF (p_dados->>'to')::date IS NULL OR (p_dados->>'to')::date<(p_dados->>'from')::date OR (p_dados->>'to')::date-(p_dados->>'from')::date>366 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo'; END IF;
    SELECT array_agg(DISTINCT x ORDER BY x) INTO dates FROM (SELECT unnest(dates) x UNION SELECT x::date FROM generate_series((p_dados->>'from')::date,(p_dados->>'to')::date,'1 day') x) s;
   END IF;
   scope_dates:=dates;
   IF p_acao='vacation_replace' THEN
    SELECT ARRAY(SELECT DISTINCT x::date FROM jsonb_array_elements_text(p_dados->'scope_dates') x ORDER BY x::date) INTO scope_dates;
    IF coalesce(cardinality(scope_dates),0) NOT BETWEEN 1 AND 367 OR EXISTS(SELECT 1 FROM unnest(dates) x WHERE NOT x=ANY(scope_dates)) THEN RAISE EXCEPTION 'VALIDATION_ERROR: âmbito férias'; END IF;
   ELSIF coalesce(cardinality(dates),0) NOT BETWEEN 1 AND 367 THEN RAISE EXCEPTION 'VALIDATION_ERROR: datas'; END IF;
   IF p_dados ? 'fraction' OR p_dados ? 'hours' OR p_dados ? 'period' THEN RAISE EXCEPTION 'VACATION_FULL_DAYS_ONLY'; END IF;
   IF p_acao IN('vacation_set','vacation_replace') THEN SELECT ARRAY(SELECT x FROM unnest(dates) x WHERE extract(isodow FROM x)<6 AND NOT x=ANY(coalesce(cfg.holiday_dates,'{}')) ORDER BY x) INTO dates; END IF;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.data,x.id),'[]') INTO before FROM public.ausencias x WHERE colaborador_id=person AND data=ANY(scope_dates);
   IF p_acao IN('vacation_set','vacation_replace') AND EXISTS(SELECT 1 FROM unnest(dates) x JOIN public.colaboradores c ON c.id=person WHERE c.data_admissao IS NULL OR c.data_admissao>x OR c.data_saida<=x) THEN RAISE EXCEPTION 'COLLABORATOR_UNAVAILABLE'; END IF;
   IF p_acao IN('vacation_set','vacation_replace') AND (EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=ANY(dates) AND tipo<>'ferias')
    OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=ANY(dates))
    OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=ANY(dates))) AND NOT coalesce((p_dados->>'admin_override')::boolean,false)
   THEN RAISE EXCEPTION 'REGULARIZATION_REQUIRED'; END IF;
   pending:=NOT coalesce(cfg.calendar_complete,false) OR EXISTS(SELECT 1 FROM unnest(dates) x WHERE NOT extract(year FROM x)::integer=ANY(coalesce(cfg.calendar_validated_years,'{}')));
   after:=jsonb_build_object('dates',dates,'scope_dates',scope_dates,'consumed_days',CASE WHEN pending THEN NULL ELSE cardinality(dates) END,'pending_rule',false,'calendar_pending',pending,'override',coalesce((p_dados->>'admin_override')::boolean,false));
  END IF;
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  m:=(p_dados->>'month')::date; IF extract(day FROM m)<>1 OR m IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: competência'; END IF;
  SELECT * INTO v FROM public.folha_vencimentos WHERE colaborador_id=person AND competencia=m FOR UPDATE;
  entity:=coalesce(v.id,req);before:=to_jsonb(v);rev:=coalesce(v.revision,0);facts:=folha_privado.payroll_facts(person,m);
  IF p_acao='payroll_save' THEN
   IF v.estado IS NOT NULL AND v.estado<>'draft' THEN RAISE EXCEPTION 'PAYROLL_FROZEN'; END IF;
   IF jsonb_typeof(coalesce(p_dados->'manual','{}'))<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(p_dados->'manual','{}')) x WHERE x NOT IN('km','allowance','note')) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   FOR item IN SELECT jsonb_build_object('k',x.key,'v',x.value) FROM jsonb_each(coalesce(p_dados->'manual','{}')) x LOOP
    IF item->>'k'<>'note' AND item->'v'<>'null'::jsonb AND (jsonb_typeof(item->'v')<>'number' OR (item->>'v')::numeric<0) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   END LOOP;
   after:=jsonb_build_object('estado','draft','facts',facts,'manual',coalesce(p_dados->'manual','{}'));
  ELSE
   IF v.id IS NULL OR v.factos<>facts THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
   IF p_acao IN('payroll_validate','payroll_close') AND (NOT coalesce(cfg.calendar_complete,false) OR NOT extract(year FROM m)::integer=ANY(cfg.calendar_validated_years) OR jsonb_array_length(facts->'pending_days')>0 OR jsonb_array_length(facts->'legacy_days')>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'sheets') x WHERE x->>'state'<>'registered' OR (x->>'special_day')::boolean AND NOT coalesce((x->>'special_reviewed')::boolean,false)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'absences') x WHERE x->>'state'='ausente_pendente') OR v.manuais->>'km' IS NULL OR v.manuais->>'allowance' IS NULL) THEN RAISE EXCEPTION 'PAYROLL_PENDING_FACTS: regularize factos, calendário, quilómetros e ajudas de custo'; END IF;
   IF p_acao='payroll_reopen' AND v.estado IN('validated','closed') THEN after:=jsonb_build_object('estado','draft','facts',facts,'manual',v.manuais);
   ELSIF p_acao='payroll_validate' AND v.estado='draft' THEN after:=jsonb_build_object('estado','validated','facts',facts,'manual',v.manuais);
   ELSIF p_acao='payroll_close' AND v.estado='validated' THEN
    after:=jsonb_build_object('estado','closed','facts',facts,'manual',v.manuais,'recibos_recebidos',true);
   ELSIF p_acao='payroll_export' THEN RAISE EXCEPTION 'OFFICIAL_EXPORTER_REQUIRED: modelo e exportador oficial ainda não instalados';
   ELSE RAISE EXCEPTION 'PAYROLL_TRANSITION_INVALID'; END IF;
  END IF;
 ELSIF p_acao IN('task_report','task_confirm') THEN
  entity:=(p_dados->>'task_id')::uuid;
  SELECT p.* INTO task FROM public.planeamento_itens p JOIN public.fases fase ON fase.id=p.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE p.id=entity AND o.empresa_id=u.empresa_id AND fase.obra_id=w FOR UPDATE OF p FOR SHARE OF fase,o;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501'; END IF;
  PERFORM folha_privado.obra(w);
  SELECT * INTO t FROM public.folha_tarefas_reportes WHERE tarefa_id=entity FOR UPDATE;before:=to_jsonb(t);rev:=coalesce(t.revision,0);
  IF p_acao='task_report' THEN
   IF (u.funcao<>'encarregado' AND NOT folha_privado.superuser()) OR task.estado='concluido' OR task.arquivado_em IS NOT NULL OR t.id IS NOT NULL THEN RAISE EXCEPTION 'TASK_REPORT_INVALID'; END IF;
   after:=jsonb_build_object('estado','reported');
  ELSE
   IF (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR t.estado IS DISTINCT FROM 'reported' OR task.estado<>'concluido' THEN RAISE EXCEPTION 'PLANNING_CONFIRMATION_REQUIRED'; END IF;
   after:=jsonb_build_object('estado','confirmed');
  END IF;
 ELSE RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
 IF expected IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',before,'after',after,'config',to_jsonb(cfg))::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='configure_he_eligibility' THEN
  INSERT INTO public.folha_config_empresa(empresa_id,he_eligible_roles,revision) VALUES(u.empresa_id,ARRAY(SELECT x FROM jsonb_array_elements_text(after->'roles') x),rev+1) ON CONFLICT(empresa_id) DO UPDATE SET he_eligible_roles=excluded.he_eligible_roles,revision=excluded.revision;
 ELSIF p_acao='absence_confirm' THEN
  previous_request:=current_setting('folha.request_id',true);PERFORM set_config('folha.request_id',req::text,true);
  UPDATE public.ausencias SET estado=after->>'estado',comentario=p_dados->>'reason' WHERE id=entity;
  PERFORM set_config('folha.request_id',coalesce(previous_request,''),true);
 ELSIF p_acao='special_review' THEN
  UPDATE public.folha_registos SET special_reviewed_by=u.id,special_reviewed_at=now(),revision=revision+1,atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=entity RETURNING * INTO f;
  after:=after||to_jsonb(f)||jsonb_build_object('special_reviewed',true);
 ELSIF p_acao='he_process' THEN
  UPDATE public.folha_he SET processado_em=now(),processado_por=u.id,revision=revision+1 WHERE id=entity;
  UPDATE public.alertas SET estado='resolvido',resolvido_em=now(),resolvido_por=u.id WHERE empresa_id=u.empresa_id AND entidade_id=entity AND tipo='folha_he_processamento' AND estado='pendente';
 ELSIF p_acao='configure_company' THEN
  INSERT INTO public.folha_config_empresa(empresa_id,office_expected_minutes,correction_days,overtime_enabled,calendar_complete,holiday_dates,payroll_rules_ready,official_template_hash,revision)
   VALUES(u.empresa_id,(after->>'office_expected_minutes')::integer,(after->>'correction_days')::integer,(after->>'overtime_enabled')::boolean,(after->>'calendar_complete')::boolean,
    ARRAY(SELECT x::date FROM jsonb_array_elements_text(after->'holiday_dates') x),(after->>'payroll_rules_ready')::boolean,after->>'official_template_hash',rev+1)
   ON CONFLICT(empresa_id) DO UPDATE SET office_expected_minutes=excluded.office_expected_minutes,correction_days=excluded.correction_days,overtime_enabled=excluded.overtime_enabled,calendar_complete=excluded.calendar_complete,
    holiday_dates=excluded.holiday_dates,payroll_rules_ready=excluded.payroll_rules_ready,official_template_hash=excluded.official_template_hash,revision=excluded.revision;
  UPDATE public.folha_config_empresa SET calendar_validated_years=ARRAY(SELECT x::integer FROM jsonb_array_elements_text(after->'calendar_validated_years') x) WHERE empresa_id=u.empresa_id;
 ELSIF p_acao='configure_schedule' THEN
  INSERT INTO public.folha_horarios VALUES(w,u.empresa_id,after->'intervals',(after->>'expected_minutes')::integer,rev+1)
   ON CONFLICT(obra_id) DO UPDATE SET intervals=excluded.intervals,expected_minutes=excluded.expected_minutes,revision=excluded.revision;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  UPDATE public.folha_he SET estado=after->>'estado',revision=rev+1,prazo_processamento=prazo_processamento WHERE id=entity RETURNING * INTO h;
  -- HR-27: recognized HE is informational; no processing alert or payment.

 ELSIF p_acao='vacation_entitlement' THEN
  INSERT INTO public.folha_direitos_ferias(empresa_id,colaborador_id,ano,dias,fonte,revision,saldo_transitado,validade_transitado,dias_adicionais,autorizacao) VALUES(u.empresa_id,person,(after->>'year')::integer,(after->>'days')::numeric,after->>'source',rev+1,(after->>'carry')::integer,(after->>'carry_expires')::date,(after->>'additional')::integer,after->>'authorization')
   ON CONFLICT(colaborador_id,ano) DO UPDATE SET dias=excluded.dias,fonte=excluded.fonte,revision=excluded.revision,saldo_transitado=excluded.saldo_transitado,validade_transitado=excluded.validade_transitado,dias_adicionais=excluded.dias_adicionais,autorizacao=excluded.autorizacao;
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace') THEN
  -- Correlation only; this setting never grants permissions. Triggers resolve actor/tenant independently.
  previous_request:=current_setting('folha.request_id',true);PERFORM set_config('folha.request_id',req::text,true);
  IF p_acao='vacation_remove' THEN DELETE FROM public.ausencias WHERE colaborador_id=person AND data=ANY(dates) AND tipo='ferias';
  ELSE
   IF p_acao='vacation_replace' THEN DELETE FROM public.ausencias WHERE colaborador_id=person AND data=ANY(scope_dates) AND NOT data=ANY(dates) AND tipo='ferias'; END IF;
   FOREACH a IN ARRAY dates LOOP
    IF NOT EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=a AND tipo='ferias') THEN
     INSERT INTO public.ausencias(colaborador_id,data,tipo,estado,comentario) VALUES(person,a,'ferias','confirmada',p_dados->>'reason');
    END IF;
   END LOOP;
  END IF;
  INSERT INTO public.folha_ferias_revisoes VALUES(u.empresa_id,person,rev+1) ON CONFLICT(colaborador_id) DO UPDATE SET revision=excluded.revision;
  PERFORM set_config('folha.request_id',coalesce(previous_request,''),true);
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close','payroll_reopen') THEN
  INSERT INTO public.folha_vencimentos(id,empresa_id,colaborador_id,competencia,factos,manuais,estado,revision,criado_por,atualizado_por)
   VALUES(entity,u.empresa_id,person,m,after->'facts',after->'manual',after->>'estado',rev+1,u.id,u.id)
   ON CONFLICT(colaborador_id,competencia) DO UPDATE SET factos=excluded.factos,manuais=excluded.manuais,estado=excluded.estado,revision=excluded.revision,atualizado_por=u.id,atualizado_em=now();
  IF p_acao='payroll_close' THEN UPDATE public.folha_vencimentos SET recibos_recebidos_em=now(),recibos_recebidos_por=u.id WHERE id=entity; ELSIF p_acao='payroll_reopen' THEN UPDATE public.folha_vencimentos SET recibos_recebidos_em=NULL,recibos_recebidos_por=NULL WHERE id=entity; END IF;
 ELSIF p_acao='task_report' THEN
  INSERT INTO public.folha_tarefas_reportes(empresa_id,obra_id,tarefa_id,estado,reportado_por) VALUES(u.empresa_id,w,entity,'reported',u.id);
  INSERT INTO public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave)
   SELECT u.empresa_id,w,'folha_conclusao_reportada','planeamento_item',entity,'Conclusão reportada: validar no Planeamento',
   format('Obra %s · tarefa %s · %s. Reportado por %s em %s. Aguarda confirmação no Planeamento.',(SELECT numero FROM public.obras WHERE id=w),coalesce(to_jsonb(task)->>'codigo',entity::text),coalesce(to_jsonb(task)->>'descricao',''),u.nome,now()),
   (now() AT TIME ZONE 'Europe/Lisbon')::date,r.utilizador_id,false,req
   FROM public.obra_responsaveis r JOIN public.utilizadores dest ON dest.id=r.utilizador_id WHERE r.obra_id=w AND r.papel IN('diretor_obra','adjunto') AND dest.ativo AND dest.empresa_id=u.empresa_id;
 ELSE
  UPDATE public.folha_tarefas_reportes SET estado='confirmed',confirmado_por=u.id,confirmado_em=now(),revision=rev+1 WHERE tarefa_id=entity;
  UPDATE public.alertas SET estado='resolvido',resolvido_por=u.id,resolvido_em=now() WHERE empresa_id=u.empresa_id AND obra_id=w AND entidade_id=entity AND entidade_tipo='planeamento_item' AND tipo='folha_conclusao_reportada' AND estado='pendente';
 END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,p_acao,entity,before,after,u.id,req,p_dados->>'reason');
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',rev+1,'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 u:=folha_privado.ator();
 IF p_acao='he_process' THEN RAISE EXCEPTION 'HR27_HE_INFORMATIONAL_ONLY: a plataforma não processa nem paga HE' USING ERRCODE='22023'; END IF;
 IF p_acao IN('configure_schedule','daily_activation','schedule_retro_correct','daily_reference_correct','daily_he_validate','daily_he_disregard') THEN RETURN public.fn_folha_diaria_gestao_v2(p_acao,p_dados,p_confirmar,p_versao); END IF;
 IF p_acao IN('payroll_validate','payroll_close') AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo' USING ERRCODE='42501'; END IF;
 IF p_acao IN('payroll_validate','payroll_close') AND EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.empresa_id=u.empresa_id AND a.colaborador_id=(p_dados->>'person_id')::uuid AND a.data>=(p_dados->>'month')::date AND a.data<((p_dados->>'month')::date+interval '1 month')::date AND a.ativa AND (cardinality(array_remove(a.pendencias,'he_validada_aguarda_processamento'))>0 OR a.referencia_estado<>'capturada' OR a.falta_minutes IS DISTINCT FROM 0 OR a.excedente_minutes IS NULL OR a.he_estado NOT IN('nenhum','validada','nao_considerada'))) THEN RAISE EXCEPTION 'PAYROLL_DAILY_PENDING: avaliação diária/HE aguarda regularização ou processamento'; END IF;
 RETURN folha_privado.diaria_gestao_preservada(p_acao,p_dados,p_confirmar,p_versao);
END $$;
DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_hr27_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_hr27_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE n.nspname='primeline_hr27_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_hr27_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'HR27_BACKUP_NOT_PRIVATE'; END IF;
FOR r IN SELECT * FROM primeline_hr27_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'HR27_DATA_DRIFT: %',r.tabela;END IF;END LOOP;
END $data$;
DO $hours_dependencies$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.ator()') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='176c4fb030401fb45c89f3cd1616a9d26e9e15b691ff524a33dfc8d233c6b079' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.ator()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.obra(uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='731f5289cd29bdb7f7d69723fabb76cbb8b8e577bb474c679f991c7271d9788e' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.obra(uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.lock_dia(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='b29022304f316e25dd34bae7a1e1906a0dfd72bd041a1d658338cc8394745502' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.lock_dia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.local(uuid,uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9eb2f0d8b7e52d5280f0798c48cb8ec84377281c1e13706bc066b1cf3765070b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.local(uuid,uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_contexto_v2(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5ca6e224708a655a9c778fa6a5701b39e6c0aab8dbf0a01a87ffb77d42ea095' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner AND x.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: public.fn_folha_contexto_v2(date,uuid)';END IF;
END $hours_dependencies$;DO $guard$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
IF to_regclass('public.folha_jornadas_individuais_versoes') IS NULL THEN RAISE EXCEPTION 'HR27_REQUIRES_AD03';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred) THEN RAISE EXCEPTION 'HR27_AD14_TRIGGER_DRIFT';END IF;
IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE folha_privado.diaria_ad14_valida(a,true) IS NOT TRUE OR folha_privado.jornada_ad03_avaliacao_valida(a) IS NOT TRUE) THEN RAISE EXCEPTION 'HR27_INVALID_EXISTING_EVALUATION';END IF;
END $guard$;
SELECT 'HR27_INSTALLED_NOT_ACTIVATED' resultado;COMMIT;
