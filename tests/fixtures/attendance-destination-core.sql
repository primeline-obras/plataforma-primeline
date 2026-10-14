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
-- SAVE_HELPER
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
