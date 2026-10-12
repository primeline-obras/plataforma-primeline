-- Falta contextual V2: instalação local proposta; NÃO aplicada em produção.
BEGIN;
SET LOCAL lock_timeout='10s';
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname,pg_get_expr(conbin,conrelid) expr FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%tipo%' LOOP
  EXECUTE format('ALTER TABLE public.ausencias DROP CONSTRAINT %I',c.conname);
  EXECUTE format('ALTER TABLE public.ausencias ADD CONSTRAINT %I CHECK ((%s) OR (tipo=''falta_justificada_pendente'' AND estado=''ausente_pendente''))',c.conname,c.expr);
 END LOOP;
END $$;
CREATE FUNCTION folha_privado.proteger_classificacao_falta() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF OLD.tipo='falta_justificada_pendente' AND (NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.estado IS DISTINCT FROM OLD.estado) THEN
  IF NOT folha_privado.adm() OR NEW.tipo NOT IN('falta_justificada_com_remuneracao','falta_justificada_sem_remuneracao') THEN RAISE EXCEPTION 'ABSENCE_CLASSIFICATION_REQUIRED: classificação administrativa obrigatória' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION folha_privado.proteger_classificacao_falta() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_falta_classificacao BEFORE UPDATE OF tipo,estado ON public.ausencias FOR EACH ROW EXECUTE FUNCTION folha_privado.proteger_classificacao_falta();
CREATE FUNCTION public.fn_folha_falta_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; p uuid; w uuid; d date; req uuid; a public.ausencias; op folha_privado.operacoes; payload jsonb; token text; result jsonb; before jsonb; row_data jsonb; choice text; today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator();
 SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo IS TRUE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão inativa' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 req:=(p_dados->>'request_id')::uuid;
 IF p_dados->>'version' IS DISTINCT FROM '2' OR req IS NULL OR p_confirmar IS NULL OR p_acao IS NULL OR p_acao NOT IN('absence_report','absence_classify') THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao='absence_report' THEN
  p:=(p_dados->'key'->>'person_id')::uuid;w:=(p_dados->>'work_id')::uuid;d:=(p_dados->>'date')::date;choice:=p_dados->>'choice';
  IF u.funcao<>'encarregado' OR w IS NULL OR p IS NULL OR p_dados->'key'->>'kind' IS DISTINCT FROM 'primeline' THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas equipa Primeline do Encarregado' USING ERRCODE='42501'; END IF;
  IF d IS NULL OR d NOT BETWEEN today-1 AND today THEN RAISE EXCEPTION 'DATE_WINDOW: apenas hoje e ontem'; END IF;
  IF choice IS NULL OR choice NOT IN('justificada','injustificada') THEN RAISE EXCEPTION 'VALIDATION_ERROR: falta'; END IF;
  PERFORM folha_privado.obra(w,true);
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id AND c.data_saida IS NULL AND c.utilizador_id IS DISTINCT FROM u.id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=p AND e.obra_id=w AND e.empresa_id=u.empresa_id AND e.inicio<=d AND (e.fim IS NULL OR e.fim>d)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fora da equipa' USING ERRCODE='42501'; END IF;
 ELSE
  IF NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: classificação administrativa' USING ERRCODE='42501'; END IF;
  SELECT x.* INTO a FROM public.ausencias x JOIN public.colaboradores c ON c.id=x.colaborador_id AND c.empresa_id=u.empresa_id WHERE x.id=(p_dados->>'id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501'; END IF;
  p:=a.colaborador_id;d:=a.data;
  choice:=p_dados->>'classification';
  IF choice IS NULL OR choice NOT IN('falta_justificada_com_remuneracao','falta_justificada_sem_remuneracao') OR nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: classificação e motivo obrigatórios'; END IF;
 END IF;
 PERFORM folha_privado.lock_dia(p,d);
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token,'summary','Ocorrência já registada.'); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 IF p_acao='absence_report' THEN
  IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.lancamentos_mao_obra WHERE colaborador_id=p AND data=d) OR EXISTS(SELECT 1 FROM public.horas_extraordinarias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'POINT_CONFLICT: já existe ponto ou horas neste dia; regularização administrativa necessária'; END IF;
  IF EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT: já existe uma ausência neste dia'; END IF;
  row_data:=folha_privado.linha(p,w,d,'primeline');
  IF row_data->>'conflict' IS NOT NULL THEN RAISE EXCEPTION 'POINT_CONFLICT: regularize o conflito existente'; END IF;
  before:='null'::jsonb;
 ELSE
  SELECT * INTO a FROM public.ausencias WHERE id=(p_dados->>'id')::uuid FOR UPDATE;
  IF a.tipo<>'falta_justificada_pendente' OR a.estado<>'ausente_pendente' THEN RAISE EXCEPTION 'STALE_REVISION: ocorrência já classificada' USING ERRCODE='40001'; END IF;
  before:=to_jsonb(a);
 END IF;
 token:=md5(payload::text||before::text||coalesce(row_data::text,''));
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'summary',CASE WHEN p_acao='absence_report' THEN 'Confirmar falta? A pessoa permanece na equipa; não serão criadas horas.' ELSE 'Confirmar classificação administrativa?' END); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='absence_report' THEN
  INSERT INTO public.ausencias(colaborador_id,data,tipo,estado,comentario) VALUES(p,d,CASE WHEN choice='justificada' THEN 'falta_justificada_pendente' ELSE 'falta_injustificada' END,'ausente_pendente','Ocorrência reportada pelo Encarregado; '||choice) RETURNING * INTO a;
 ELSE
  UPDATE public.ausencias SET tipo=choice,estado=CASE WHEN choice='falta_justificada_com_remuneracao' THEN 'confirmada' ELSE 'justificada' END,comentario=p_dados->>'reason' WHERE id=a.id RETURNING * INTO a;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason) VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,p,'primeline',d,p_acao,before,to_jsonb(a),1,u.id,req,coalesce(p_dados->>'reason','Ocorrência de falta'));
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',1,'absence',to_jsonb(a),'changed_keys',jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p,'work_id',w,'date',d)));
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.fn_folha_falta_v2(text,jsonb,boolean,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_falta_v2(text,jsonb,boolean,text) TO authenticated;
COMMIT;
