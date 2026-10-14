-- LOCAL ONLY. Requires prior HR27/Faltou/readers/monthly packages.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;SELECT pg_advisory_xact_lock(61001,1);LOCK TABLE public.folha_registos,public.folha_avaliacoes_diarias,public.folha_historico,public.folha_gestao_historico,public.folha_he,public.folha_vencimentos,public.ausencias,public.colaboradores,public.quadro_equipa_permanencias,public.folha_externos_dias,public.folha_conferencias_mensais,public.folha_conferencia_historico,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;DO $hours_dependencies$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.ator()') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='176c4fb030401fb45c89f3cd1616a9d26e9e15b691ff524a33dfc8d233c6b079' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.ator()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.obra(uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='731f5289cd29bdb7f7d69723fabb76cbb8b8e577bb474c679f991c7271d9788e' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.obra(uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.lock_dia(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='b29022304f316e25dd34bae7a1e1906a0dfd72bd041a1d658338cc8394745502' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.lock_dia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.local(uuid,uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9eb2f0d8b7e52d5280f0798c48cb8ec84377281c1e13706bc066b1cf3765070b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.local(uuid,uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_contexto_v2(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5ca6e224708a655a9c778fa6a5701b39e6c0aab8dbf0a01a87ffb77d42ea095' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner AND x.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: public.fn_folha_contexto_v2(date,uuid)';END IF;
END $hours_dependencies$;DO $functions$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_pessoal(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='26d7f517fbb64f5ab6e081b0b97fc295e6701e0b98529157c278036258e97d8b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_pessoal(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_factos(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='22bca9e4ee22d1550d633da0200511474a85a798e25ceb25b620d0785c7a6c80' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_factos(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_recalcular(uuid,date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='dbc612ef9301d7d6e909d8fbecf938ac9d63940d06cab6b883c2f685207d81d8' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_recalcular(uuid,date,uuid)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_horas_contexto_v3(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='4162758ceba25fab4a3610746de8c92f8fb5548f9970d8a06997b3f8d0ca8f1b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner AND a.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: public.fn_folha_horas_contexto_v3(date,uuid)';END IF;
END $functions$;DO $absent$ BEGIN IF to_regprocedure('folha_privado.destino_autorizar_v3(uuid,uuid,text,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.save_destino_v3(jsonb,uuid,date,uuid,boolean,jsonb)') IS NOT NULL OR to_regprocedure('public.fn_folha_destino_operar_v3(jsonb,boolean,text)') IS NOT NULL OR to_regprocedure('public.fn_folha_dia_normal_v3(jsonb,boolean,text)') IS NOT NULL THEN RAISE EXCEPTION 'DESTINATION_PRESENT_OR_PARTIAL';END IF;END $absent$;DO $constraint$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_avaliacoes_diarias_modo_dia_check' AND contype='c' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((modo_dia = ANY (ARRAY[''personalizado''::text, ''misto''::text])))') THEN RAISE EXCEPTION 'DESTINATION_CONSTRAINT_DRIFT';END IF;END $constraint$;DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_destino_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_destino_backup' AND a.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE n.nspname='primeline_destino_backup' AND a.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_destino_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'DESTINATION_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_destino_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'DESTINATION_DATA_DRIFT';END IF;END LOOP;END $data$;ALTER TABLE public.folha_avaliacoes_diarias DROP CONSTRAINT folha_avaliacoes_diarias_modo_dia_check;ALTER TABLE public.folha_avaliacoes_diarias ADD CONSTRAINT folha_avaliacoes_diarias_modo_dia_check CHECK(modo_dia IN('personalizado','misto','normal_individual'));CREATE OR REPLACE FUNCTION folha_privado.diaria_pessoal(p uuid,d date) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) x WHERE f.colaborador_id=p AND f.data=d AND (x->>'mode'='personalizado' OR x->'daily_scope'='true'::jsonb))
$$;
CREATE OR REPLACE FUNCTION folha_privado.diaria_factos(p uuid,d date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('canonical',jsonb_build_array('folha_factos_v1',c.empresa_id,p,d,
 coalesce((SELECT jsonb_agg(jsonb_build_array(f.id,f.revision,f.tipo_local,f.obra_id,
 (SELECT jsonb_agg(jsonb_build_array(i.ordinality,i.x->>'start',i.x->>'end',i.x->>'period',i.x->>'mode')||CASE WHEN i.x->'daily_scope'='true'::jsonb THEN '["individual_v3"]'::jsonb ELSE '[]'::jsonb END ORDER BY i.ordinality) FROM jsonb_array_elements(f.intervals) WITH ORDINALITY i(x,ordinality)),f.special_day,f.special_reviewed_by,f.special_reviewed_at) ORDER BY f.id::text COLLATE "C") FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),'[]'::jsonb),
 coalesce((SELECT jsonb_agg(jsonb_build_array(a.id,a.tipo,a.estado) ORDER BY a.id::text COLLATE "C") FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=d),'[]'::jsonb)),
 'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision) ORDER BY f.id::text COLLATE "C") FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),'[]'::jsonb),
 'minutes',coalesce((SELECT sum(f.minutes)::integer FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),0),
 'mixed',EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) i WHERE f.colaborador_id=p AND f.data=d AND i->>'mode' IS DISTINCT FROM 'personalizado'),
 'open',EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) i WHERE f.colaborador_id=p AND f.data=d AND i->>'end' IS NULL),
 'conflict',EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=d) OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra a WHERE a.colaborador_id=p AND a.data=d),
 'special_pending',EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d AND f.special_day AND f.special_reviewed_at IS NULL))
 FROM public.colaboradores c WHERE c.id=p
$$;
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
 n.ativa:=personal;n.modo_dia:=CASE WHEN NOT EXISTS(SELECT 1 FROM public.folha_registos r CROSS JOIN LATERAL jsonb_array_elements(r.intervals) x WHERE r.colaborador_id=p AND r.data=d AND x->>'mode'='personalizado') THEN 'normal_individual' WHEN (f->>'mixed')::boolean THEN 'misto' ELSE 'personalizado' END;n.revision:=coalesce(old.revision,0)+1;
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
-- Local isolated operational writer. Source facts in other works are preserved.
CREATE FUNCTION folha_privado.destino_autorizar_v3(p uuid,w uuid,k text,writing boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $auth$
DECLARE u public.utilizadores;
BEGIN
 u:=folha_privado.ator();IF writing THEN PERFORM 1 FROM public.utilizadores WHERE id=u.id FOR SHARE;u:=folha_privado.ator();END IF;IF w IS NULL OR k NOT IN('primeline','external') THEN RAISE EXCEPTION 'DESTINATION_REQUIRED';END IF;
 IF writing THEN PERFORM 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id FOR SHARE;ELSE PERFORM 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id;END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: tenant' USING ERRCODE='42501';END IF;
 IF folha_privado.adm_operacional() THEN RETURN;END IF;
 IF k='external' AND u.funcao='diretor_obra' THEN
  IF writing THEN PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=w AND utilizador_id=u.id AND papel=u.funcao FOR SHARE;ELSE PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=w AND utilizador_id=u.id AND papel=u.funcao;END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: diretor destino' USING ERRCODE='42501';END IF;RETURN;
 END IF;
 IF writing AND u.funcao NOT IN('encarregado','diretor_obra','adjunto','preparador') THEN RAISE EXCEPTION 'PERMISSION_DENIED: escrita operacional' USING ERRCODE='42501';END IF;
 PERFORM folha_privado.local(p,w,writing);
END $auth$;
CREATE FUNCTION folha_privado.save_destino_v3(p jsonb,w uuid,d date,req uuid,confirmar boolean,plano jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
 row jsonb; f jsonb; state text; expected integer; window_days integer; special boolean; result public.folha_registos;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.destino_autorizar_v3(person,w,kind,true);u:=folha_privado.ator(); PERFORM folha_privado.lock_dia(person,d);
 IF p->'key'->>'work_id' IS DISTINCT FROM w::text OR p->'key'->>'date' IS DISTINCT FROM d::text OR kind IS NULL OR kind NOT IN('primeline','external')
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: chave'; END IF;
 row:=folha_privado.linha(person,w,d,kind); IF kind='primeline' AND EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT';END IF;
 IF kind='primeline' AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'LEGACY_CONFLICT: não misturar escritores'; END IF;
 IF kind='primeline' THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador indisponível' USING ERRCODE='42501'; END IF;
  IF u.funcao='encarregado' AND NOT folha_privado.elegivel_equipa(person,d) AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND (SELECT count(*) FROM public.colaboradores WHERE utilizador_id=u.id AND empresa_id=u.empresa_id)=1) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas equipa operacional elegível' USING ERRCODE='42501'; END IF;

 ELSE
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND (ativo OR (folha_privado.adm_operacional() OR u.funcao='diretor_obra') AND EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.externo_id=person AND f.obra_id=w AND f.data=d AND f.empresa_id=u.empresa_id)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo indisponível' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=w))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor não autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d AND empresa_id=u.empresa_id) AND NOT EXISTS(SELECT 1 FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND empresa_id=u.empresa_id AND inicio<=d AND (fim IS NULL OR fim>d)) THEN RAISE EXCEPTION 'EXTERNAL_DAY_REQUIRED'; END IF;
 END IF;
 IF row->>'conflict' IS NOT NULL THEN RAISE EXCEPTION '%',row->>'conflict'; END IF;
 SELECT * INTO old FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND CASE WHEN kind='primeline' THEN colaborador_id=person ELSE externo_id=person END FOR UPDATE;
 IF kind='primeline' AND old.id IS NULL THEN SELECT revision INTO old.revision FROM folha_privado.periodos_revisoes WHERE colaborador_id=person AND obra_id IS NOT DISTINCT FROM w AND data=d; END IF;
 IF kind='external' AND u.funcao='diretor_obra' AND old.id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas correção externa existente' USING ERRCODE='42501';END IF;
 IF (p->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT folha_privado.adm_operacional() AND NOT(kind='external' AND u.funcao='diretor_obra') THEN
  window_days:=1;
  IF window_days IS NULL THEN RAISE EXCEPTION 'CORRECTION_WINDOW_UNCONFIGURED'; END IF;
  IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>window_days THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 END IF;
 IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>1 AND folha_privado.adm_operacional() AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
 f:=folha_privado.facts(p->'intervals',d); expected:=(row->>'expected_minutes')::integer;
 IF kind='primeline' THEN expected:=NULL;
 ELSIF w IS NOT NULL THEN SELECT sum((extract(epoch FROM ((h.x->>'end')::time-(h.x->>'start')::time))/60)::integer) INTO expected FROM public.folha_horarios schedule CROSS JOIN LATERAL jsonb_array_elements(schedule.intervals) h(x) WHERE schedule.obra_id=w AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->'intervals') period WHERE period->>'period'=h.x->>'period'); END IF;
 special:=extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND d=ANY(holiday_dates));
 IF EXISTS(SELECT 1 FROM public.folha_registos other,jsonb_array_elements(other.intervals) x,jsonb_array_elements(p->'intervals') y
 WHERE other.data=d AND other.obra_id IS DISTINCT FROM w AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(plano) target WHERE target->>'work_id' IS NOT DISTINCT FROM other.obra_id::text) AND (CASE WHEN kind='primeline' THEN other.colaborador_id=person ELSE other.externo_id=person END)
 AND (x->>'start')::time<coalesce((y->>'end')::time,'24:00'::time) AND (y->>'start')::time<coalesce((x->>'end')::time,'24:00'::time))
 THEN RAISE EXCEPTION 'INTERVAL_CONFLICT: outra obra'; END IF;
 state:=folha_privado.estado_efetivo((f->>'minutes')::integer,(f->>'open')::boolean,expected,row->'absence'<>'null'::jsonb,row->>'conflict' IS NOT NULL);
 IF kind='external' THEN state:=CASE WHEN row->>'conflict' IS NOT NULL OR coalesce(row->'absence'<>'null'::jsonb,false) THEN 'regularization' WHEN (f->>'open')::boolean THEN 'open' ELSE 'registered' END; expected:=NULL; END IF;

 IF NOT confirmar THEN RETURN jsonb_build_object('before',to_jsonb(old),'revision',coalesce(old.revision,0),'row',row,'facts',f,'state',state); END IF;
 IF kind='external' THEN INSERT INTO public.folha_externos_dias(externo_id,empresa_id,obra_id,data,criado_por,request_id,funcao) SELECT person,u.empresa_id,w,d,u.id,req,funcao FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d) ON CONFLICT DO NOTHING; END IF;
 IF old.id IS NOT NULL THEN
 UPDATE public.folha_registos SET expected_minutes=expected,intervals=p->'intervals',minutes=(f->>'minutes')::integer,estado=state,special_day=old.special_day,special_reviewed_at=NULL,special_reviewed_by=NULL,
 revision=old.revision+1,note=p->>'note',atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=old.id RETURNING * INTO result;
 ELSE
 INSERT INTO public.folha_registos(empresa_id,obra_id,tipo_local,data,colaborador_id,externo_id,intervals,minutes,estado,special_day,expected_minutes,revision,note,criado_por,atualizado_por,request_id)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,d,CASE WHEN kind='primeline' THEN person END,CASE WHEN kind='external' THEN person END,p->'intervals',(f->>'minutes')::integer,state,special,expected,coalesce(old.revision,0)+1,p->>'note',u.id,u.id,req)
 RETURNING * INTO result;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,kind,d,'save',to_jsonb(old),to_jsonb(result),result.revision,u.id,req,p->>'reason');
 IF kind='primeline' THEN PERFORM folha_privado.diaria_recalcular(person,d,req);END IF;
 RETURN jsonb_build_object('result',to_jsonb(result));
END $$;
CREATE FUNCTION public.fn_folha_destino_operar_v3(p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $destination$
DECLARE u public.utilizadores;p uuid:=(p_dados->>'person_id')::uuid;w uuid:=(p_dados->>'work_id')::uuid;d date:=(p_dados->>'date')::date;k text:=p_dados->>'kind';req uuid:=(p_dados->>'request_id')::uuid;xs jsonb;all_xs jsonb;plan jsonb;before jsonb;daily jsonb;preview jsonb;data jsonb;payload jsonb;token text;outcome jsonb;op folha_privado.operacoes;result public.folha_registos;day_count integer;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator();PERFORM 1 FROM public.utilizadores WHERE id=u.id FOR SHARE;u:=folha_privado.ator();IF (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) OR (p_dados ? 'company_id' AND (p_dados->>'company_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'TENANT_HINT_MISMATCH' USING ERRCODE='42501';END IF;PERFORM folha_privado.destino_autorizar_v3(p,w,k,true);PERFORM folha_privado.lock_dia(p,d);
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001';END IF;
 IF req IS NULL OR p IS NULL OR d IS NULL OR k IS NULL OR k NOT IN('primeline','external') OR (p_dados->>'version')::integer IS DISTINCT FROM 3 OR p_confirmar IS NULL OR jsonb_typeof(p_dados->'intervals') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'intervals') NOT BETWEEN 1 AND 16 THEN RAISE EXCEPTION 'VALIDATION_ERROR';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_dados) key WHERE key NOT IN('version','request_id','person_id','work_id','date','kind','intervals','expected_revision','expected_daily_revision','reason','note')) THEN RAISE EXCEPTION 'UNKNOWN_FIELD';END IF;
 IF k='external' AND u.funcao='diretor_obra' AND nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED';END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND NOT folha_privado.adm_operacional() AND NOT(k='external' AND u.funcao='diretor_obra') THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED';END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED';END IF;
 IF k='primeline' THEN PERFORM 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;ELSE PERFORM 1 FROM public.folha_externos WHERE id=p AND empresa_id=u.empresa_id AND (ativo OR (folha_privado.adm_operacional() OR u.funcao='diretor_obra') AND EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.externo_id=p AND f.obra_id=w AND f.data=d AND f.empresa_id=u.empresa_id)) FOR UPDATE;END IF;IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM public.obras WHERE id=w AND situacao<>'em_curso') AND NOT EXISTS(SELECT 1 FROM public.folha_registos stored WHERE stored.obra_id=w AND stored.data=d AND CASE WHEN k='primeline' THEN stored.colaborador_id=p ELSE stored.externo_id=p END) THEN RAISE EXCEPTION 'DESTINATION_NOT_ACTIVE: usar referência de Garantia';END IF;
 payload:=jsonb_build_object('action','destination_save','data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',op.token);END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;RETURN op.resultado;
 END IF;
 IF EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.data=d AND CASE WHEN k='primeline' THEN f.colaborador_id=p ELSE f.externo_id=p END AND f.empresa_id<>u.empresa_id) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'intervals') x WHERE x->>'mode' IS NULL OR x->>'mode' NOT IN('normal','personalizado') OR (x->>'mode'='personalizado' AND x->>'period' IS NOT NULL) OR (x->>'mode'='normal' AND coalesce(x->>'period','') NOT IN('manha','tarde')) OR x ? 'daily_scope') THEN RAISE EXCEPTION 'PERIOD_REQUIRED';END IF;
 SELECT jsonb_agg(CASE WHEN k='primeline' THEN x||jsonb_build_object('daily_scope',true) ELSE x END ORDER BY n) INTO xs FROM jsonb_array_elements(p_dados->'intervals') WITH ORDINALITY t(x,n);
 SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.id),'[]') INTO before FROM public.folha_registos f WHERE f.data=d AND CASE WHEN k='primeline' THEN f.colaborador_id=p ELSE f.externo_id=p END;
 SELECT coalesce(jsonb_agg(x),'[]') INTO all_xs FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) x WHERE f.data=d AND f.obra_id IS DISTINCT FROM w AND CASE WHEN k='primeline' THEN f.colaborador_id=p ELSE f.externo_id=p END;
 all_xs:=all_xs||xs;IF jsonb_array_length(all_xs)>16 THEN RAISE EXCEPTION 'INTERVAL_LIMIT';END IF;PERFORM folha_privado.facts(all_xs,d);
 SELECT count(*) INTO day_count FROM public.folha_registos f WHERE f.data=d AND f.obra_id IS DISTINCT FROM w AND CASE WHEN k='primeline' THEN f.colaborador_id=p ELSE f.externo_id=p END;
 IF day_count>=4 THEN RAISE EXCEPTION 'DESTINATION_LIMIT';END IF;
 IF k='primeline' THEN
  SELECT to_jsonb(a) INTO daily FROM public.folha_avaliacoes_diarias a WHERE a.empresa_id=u.empresa_id AND a.colaborador_id=p AND a.data=d FOR UPDATE;
  IF (p_dados->>'expected_daily_revision')::integer IS DISTINCT FROM coalesce((daily->>'revision')::integer,0) THEN RAISE EXCEPTION 'STALE_REVISION: diária' USING ERRCODE='40001';END IF;
  IF EXISTS(SELECT 1 FROM public.folha_he h JOIN public.folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=p AND f.data=d) THEN RAISE EXCEPTION 'NORMAL_HE_REQUIRES_ADMIN_REVIEW';END IF;
 END IF;
 data:=jsonb_build_object('key',jsonb_build_object('kind',k,'person_id',p,'work_id',w,'date',d),'intervals',xs,'expected_revision',p_dados->'expected_revision','reason',p_dados->>'reason','note',p_dados->>'note');
 plan:=jsonb_build_array(jsonb_build_object('work_id',w,'intervals',xs));
 preview:=folha_privado.save_destino_v3(data,w,d,req,false,plan);
 token:=encode(sha256(convert_to(jsonb_build_object('actor',u.id,'tenant',u.empresa_id,'payload',payload,'before',before,'daily',daily,'preview',preview,'reference',CASE WHEN k='primeline' AND daily IS NULL THEN folha_privado.diaria_referencia(p,d) END)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',token,'preview',jsonb_build_object('work_id',w,'person_id',p,'intervals',xs,'minutes',preview->'facts'->'minutes'));END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;
 PERFORM folha_privado.save_destino_v3(data,w,d,req,true,plan);
 SELECT * INTO result FROM public.folha_registos f WHERE f.empresa_id=u.empresa_id AND f.obra_id=w AND f.data=d AND CASE WHEN k='primeline' THEN f.colaborador_id=p ELSE f.externo_id=p END;
 outcome:=jsonb_build_object('version',3,'committed',true,'request_id',req,'record',to_jsonb(result),'changed_keys',jsonb_build_array(jsonb_build_object('kind',k,'person_id',p,'work_id',w,'date',d)));
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,outcome,now());RETURN outcome;
END $destination$;
REVOKE ALL ON FUNCTION folha_privado.destino_autorizar_v3(uuid,uuid,text,boolean),folha_privado.save_destino_v3(jsonb,uuid,date,uuid,boolean,jsonb),public.fn_folha_destino_operar_v3(jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_destino_operar_v3(jsonb,boolean,text) TO authenticated;
CREATE FUNCTION public.fn_folha_dia_normal_v3(p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $normalbatch$
DECLARE u public.utilizadores;req uuid:=(p_dados->>'request_id')::uuid;w uuid:=(p_dados->>'work_id')::uuid;d date:=(p_dados->>'date')::date;person jsonb;child jsonb;preview jsonb;previews jsonb:='[]';outcomes jsonb:='[]';token text;payload jsonb;op folha_privado.operacoes;outcome jsonb;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001';END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);u:=folha_privado.ator();PERFORM 1 FROM public.utilizadores WHERE id=u.id FOR SHARE;u:=folha_privado.ator();IF (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) OR (p_dados ? 'company_id' AND (p_dados->>'company_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'TENANT_HINT_MISMATCH' USING ERRCODE='42501';END IF;
 IF req IS NULL OR d IS NULL OR w IS NULL OR p_confirmar IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 3 OR jsonb_typeof(p_dados->'people') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'people') NOT BETWEEN 1 AND 100 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'people') x GROUP BY x->>'kind',x->>'person_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'NORMAL_BATCH_INVALID';END IF;
 FOR person IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'kind',value->>'person_id' LOOP
  PERFORM folha_privado.destino_autorizar_v3((person->>'person_id')::uuid,w,person->>'kind',true);PERFORM folha_privado.lock_dia((person->>'person_id')::uuid,d);
  IF person->>'kind'='primeline' THEN PERFORM 1 FROM public.colaboradores WHERE id=(person->>'person_id')::uuid AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;ELSE PERFORM 1 FROM public.folha_externos WHERE id=(person->>'person_id')::uuid AND empresa_id=u.empresa_id AND ativo FOR UPDATE;END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501';END IF;
 END LOOP;
 payload:=jsonb_build_object('action','normal_batch','data',p_dados);SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';END IF;IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',op.token);END IF;IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;RETURN op.resultado;END IF;
 FOR person IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'kind',value->>'person_id' LOOP
  IF EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.data=d AND CASE WHEN person->>'kind'='primeline' THEN f.colaborador_id=(person->>'person_id')::uuid ELSE f.externo_id=(person->>'person_id')::uuid END) THEN RAISE EXCEPTION 'NORMAL_DAY_ALREADY_REGISTERED: não substituir factos';END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(person->'intervals') x WHERE x->>'mode' IS DISTINCT FROM 'normal') THEN RAISE EXCEPTION 'NORMAL_BATCH_INVALID';END IF;
  child:=jsonb_build_object('version',3,'request_id',md5(req::text||':'||(person->>'kind')||':'||(person->>'person_id'))::uuid,'work_id',w,'date',d,'kind',person->>'kind','person_id',person->>'person_id','expected_revision',0,'expected_daily_revision',person->'expected_daily_revision','intervals',person->'intervals','reason',p_dados->>'reason');
  preview:=public.fn_folha_destino_operar_v3(child,false,NULL);previews:=previews||jsonb_build_array(jsonb_build_object('body',child,'token',preview->>'versao'));
 END LOOP;
 token:=encode(sha256(convert_to(jsonb_build_object('actor',u.id,'tenant',u.empresa_id,'payload',payload,'previews',previews)::text,'UTF8')),'hex');IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',token,'people_count',jsonb_array_length(previews));END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;
 FOR preview IN SELECT value FROM jsonb_array_elements(previews) LOOP outcomes:=outcomes||jsonb_build_array(public.fn_folha_destino_operar_v3(preview->'body',true,preview->>'token'));END LOOP;
 outcome:=jsonb_build_object('version',3,'committed',true,'request_id',req,'results',outcomes);INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,outcome,now());RETURN outcome;
END $normalbatch$;
REVOKE ALL ON FUNCTION public.fn_folha_dia_normal_v3(jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;GRANT EXECUTE ON FUNCTION public.fn_folha_dia_normal_v3(jsonb,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_folha_horas_contexto_v3(p_data date,p_obra_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $context$
DECLARE u public.utilizadores;c jsonb;row_data jsonb;rows jsonb:='[]';j public.folha_jornadas_individuais_versoes;cut date;
BEGIN
 u:=folha_privado.ator();c:=public.fn_folha_contexto_v2(p_data,p_obra_id);SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 FOR row_data IN SELECT value FROM jsonb_array_elements(c->'rows') LOOP
  j:=NULL;IF cut IS NOT NULL AND p_data>=cut THEN SELECT * INTO j FROM public.folha_jornadas_individuais_versoes WHERE empresa_id=u.empresa_id AND colaborador_id=(row_data->>'person_id')::uuid AND vigente_desde<=p_data AND (vigente_ate IS NULL OR vigente_ate>p_data);END IF;
  rows:=rows||jsonb_build_array(row_data||jsonb_build_object('individual_reference',CASE WHEN j.id IS NULL THEN NULL ELSE jsonb_build_object('confirmed',true,'source','individual','version_id',j.id,'revision',j.revision,'effective_from',j.vigente_desde,'effective_to',j.vigente_ate,'week',j.semana) END));
 END LOOP;
 RETURN c||jsonb_build_object('version',3,'rows',rows,'he_policy','HR-27','reference_edit_capability',false,'operational_write_capabilities',jsonb_build_object('existing_periods_save',true,'neutral_faltou',true,'free_destinations',false,'normal_individual_evaluation',true,'destination_save',true,'normal_batch',true));
END $context$;DO $hours_dependencies$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.ator()') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='176c4fb030401fb45c89f3cd1616a9d26e9e15b691ff524a33dfc8d233c6b079' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.ator()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.obra(uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='731f5289cd29bdb7f7d69723fabb76cbb8b8e577bb474c679f991c7271d9788e' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.obra(uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.lock_dia(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='b29022304f316e25dd34bae7a1e1906a0dfd72bd041a1d658338cc8394745502' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.lock_dia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.local(uuid,uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9eb2f0d8b7e52d5280f0798c48cb8ec84377281c1e13706bc066b1cf3765070b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.local(uuid,uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_contexto_v2(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5ca6e224708a655a9c778fa6a5701b39e6c0aab8dbf0a01a87ffb77d42ea095' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner AND x.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: public.fn_folha_contexto_v2(date,uuid)';END IF;
END $hours_dependencies$;DO $functions$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_pessoal(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9dd770b46c1dd1ebc42e2526847c877e9abf8999bb743825b9131e7a489dfcc0' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_pessoal(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_factos(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='4943b38546fde1a613202c485da4538fb15b61e06be07b61a24315b251659158' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_factos(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_recalcular(uuid,date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='43468884dfd93e610111bcb8ef4a7543686e7b3f46859bc3bc4bdcbcad8f9a29' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.diaria_recalcular(uuid,date,uuid)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_horas_contexto_v3(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='7f91537e7f5725857a1ee033505dd246425c986858feb7fb6cf7806964529526' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner AND a.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: public.fn_folha_horas_contexto_v3(date,uuid)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.destino_autorizar_v3(uuid,uuid,text,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='c874fba357c974db5241fc0c5c82bf92a2f012e822f8d0fb545b0f18317daa22' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.destino_autorizar_v3(uuid,uuid,text,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.save_destino_v3(jsonb,uuid,date,uuid,boolean,jsonb)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='5f563f0f26aec8760ac550bca64f11aad8e604f36ed840c683dbb48138dcf133' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner )) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: folha_privado.save_destino_v3(jsonb,uuid,date,uuid,boolean,jsonb)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_destino_operar_v3(jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='54f892399e319a1975b4ed1d6173f0da5e773adf5ca10bce46245c7c8a8f18b4' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner AND a.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: public.fn_folha_destino_operar_v3(jsonb,boolean,text)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_dia_normal_v3(jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='2fbbe648044934a9275a381eb000e82539de12e7dd8a981959e3eec507f2d802' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) a WHERE a.grantee<>proowner AND a.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'DESTINATION_FUNCTION_DRIFT: public.fn_folha_dia_normal_v3(jsonb,boolean,text)';END IF;
END $functions$;DO $constraint$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_avaliacoes_diarias_modo_dia_check' AND contype='c' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((modo_dia = ANY (ARRAY[''personalizado''::text, ''misto''::text, ''normal_individual''::text])))') THEN RAISE EXCEPTION 'DESTINATION_CONSTRAINT_DRIFT';END IF;END $constraint$;DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_destino_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_destino_backup' AND a.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE n.nspname='primeline_destino_backup' AND a.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_destino_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'DESTINATION_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_destino_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'DESTINATION_DATA_DRIFT';END IF;END LOOP;END $data$;COMMIT;
