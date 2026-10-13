-- FALTOU neutro. No remuneration decision by the foreman. No team/hour deletion.
CREATE FUNCTION folha_privado.faltou_controlado_guardar() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $guard$
BEGIN
 IF (TG_OP<>'DELETE' AND NEW.tipo='falta_reportada_pendente') OR (TG_OP<>'INSERT' AND OLD.tipo='falta_reportada_pendente') THEN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'CONTROLLED_ABSENCE_REPORT_REQUIRED' USING ERRCODE='42501';END IF;
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'ABSENCE_REPORT_HISTORY_REQUIRED';END IF;
  IF NEW.tipo='falta_reportada_pendente' AND NEW.estado IS DISTINCT FROM 'ausente_pendente' THEN RAISE EXCEPTION 'ADMIN_CLASSIFICATION_REQUIRED';END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $guard$;
CREATE TRIGGER folha_faltou_controlado BEFORE INSERT OR UPDATE OR DELETE ON public.ausencias FOR EACH ROW EXECUTE FUNCTION folha_privado.faltou_controlado_guardar();
REVOKE ALL ON FUNCTION folha_privado.faltou_controlado_guardar() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.fn_folha_faltou_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $rpc$
DECLARE u public.utilizadores;p uuid;w uuid;d date;req uuid;ab public.ausencias;op folha_privado.operacoes;payload jsonb;token text;before jsonb;after jsonb;result jsonb;reason text;choice text;today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator();SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo IS TRUE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001';END IF;
 req:=(p_dados->>'request_id')::uuid;reason:=nullif(btrim(p_dados->>'reason'),'');
 IF p_confirmar IS NULL OR p_dados->>'version' IS DISTINCT FROM '2' OR req IS NULL OR p_acao IS NULL OR p_acao NOT IN('absence_report','absence_classify') OR length(reason)>1000 THEN RAISE EXCEPTION 'VALIDATION_ERROR';END IF;
 IF p_dados ? 'empresa_id' AND p_dados->>'empresa_id' IS DISTINCT FROM u.empresa_id::text THEN RAISE EXCEPTION 'PERMISSION_DENIED: tenant' USING ERRCODE='42501';END IF;
 IF p_acao='absence_report' THEN
  p:=(p_dados->'key'->>'person_id')::uuid;w:=(p_dados->>'work_id')::uuid;d:=(p_dados->>'date')::date;
  IF u.funcao<>'encarregado' OR w IS NULL OR p IS NULL OR p_dados->'key'->>'kind' IS DISTINCT FROM 'primeline' THEN RAISE EXCEPTION 'PERMISSION_DENIED: equipa Primeline do Encarregado' USING ERRCODE='42501';END IF;
  IF p_dados ? 'choice' OR p_dados ? 'classification' THEN RAISE EXCEPTION 'FALTOU_NEUTRAL_REPORT_ONLY';END IF;
  IF p_dados->'key'->>'work_id' IS DISTINCT FROM w::text OR p_dados->'key'->>'date' IS DISTINCT FROM d::text THEN RAISE EXCEPTION 'VALIDATION_ERROR: chave';END IF;
  IF d IS NULL OR d NOT BETWEEN today-1 AND today THEN RAISE EXCEPTION 'DATE_WINDOW: apenas hoje e ontem';END IF;
  PERFORM folha_privado.obra(w,true);
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d) AND c.utilizador_id IS DISTINCT FROM u.id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias m WHERE m.colaborador_id=p AND m.obra_id=w AND m.empresa_id=u.empresa_id AND m.inicio<=d AND (m.fim IS NULL OR m.fim>d)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fora da equipa' USING ERRCODE='42501';END IF;
 ELSE
  IF NOT folha_privado.adm() OR p_dados->>'work_id' IS NOT NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: classificação administrativa' USING ERRCODE='42501';END IF;
  SELECT a.* INTO ab FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id AND c.empresa_id=u.empresa_id WHERE a.id=(p_dados->>'id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501';END IF;
  p:=ab.colaborador_id;d:=ab.data;choice:=p_dados->>'classification';
  IF choice IS NULL OR choice NOT IN('falta_injustificada','falta_justificada_com_remuneracao','falta_justificada_sem_remuneracao') OR reason IS NULL THEN RAISE EXCEPTION 'CLASSIFICATION_REASON_REQUIRED';END IF;
 END IF;
 PERFORM folha_privado.lock_dia(p,d);PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token);END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;RETURN op.resultado;
 END IF;
 IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.lancamentos_mao_obra WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.horas_extraordinarias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'POINT_CONFLICT: já existe ponto ou horas; regularização administrativa necessária';END IF;
 IF p_acao='absence_report' THEN
  IF EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT';END IF;
  IF folha_privado.linha(p,w,d,'primeline')->>'conflict' IS NOT NULL THEN RAISE EXCEPTION 'POINT_CONFLICT';END IF;
  before:='null'::jsonb;after:=jsonb_build_object('colaborador_id',p,'data',d,'tipo','falta_reportada_pendente','estado','ausente_pendente');
 ELSE
  SELECT * INTO ab FROM public.ausencias WHERE id=(p_dados->>'id')::uuid FOR UPDATE;
  IF ab.tipo<>'falta_reportada_pendente' OR ab.estado<>'ausente_pendente' OR p_dados->>'expected_type' IS DISTINCT FROM ab.tipo OR p_dados->>'expected_state' IS DISTINCT FROM ab.estado THEN RAISE EXCEPTION 'STALE_REVISION: ocorrência alterada' USING ERRCODE='40001';END IF;
  before:=to_jsonb(ab);after:=jsonb_build_object('tipo',choice,'estado',CASE WHEN choice='falta_justificada_sem_remuneracao' THEN 'justificada' ELSE 'confirmada' END,'reason',reason);
 END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('actor_id',u.id,'company_id',u.empresa_id,'payload',payload,'before',before,'after',after)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after);END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;
 IF p_acao='absence_report' THEN
  INSERT INTO public.ausencias(colaborador_id,data,tipo,estado,comentario) VALUES(p,d,'falta_reportada_pendente','ausente_pendente',coalesce(reason,'Faltou — aguarda classificação administrativa')) RETURNING * INTO ab;
 ELSE
  UPDATE public.ausencias SET tipo=after->>'tipo',estado=after->>'estado',comentario=reason WHERE id=ab.id RETURNING * INTO ab;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,p,'primeline',d,p_acao,before,to_jsonb(ab),1,u.id,req,reason);
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'absence',to_jsonb(ab),'changed_keys',jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p,'work_id',w,'date',d)));
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $rpc$;
REVOKE ALL ON FUNCTION public.fn_folha_faltou_v2(text,jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_faltou_v2(text,jsonb,boolean,text) TO authenticated;