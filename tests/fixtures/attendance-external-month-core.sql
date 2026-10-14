CREATE TABLE public.folha_externos_confirmacoes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL REFERENCES public.empresas(id),obra_id uuid NOT NULL REFERENCES public.obras(id),fornecedor_id uuid NOT NULL REFERENCES public.fornecedores(id),competencia date NOT NULL CHECK(isfinite(competencia) AND extract(day FROM competencia)=1),revision integer NOT NULL CHECK(revision>0),facts_fingerprint text NOT NULL CHECK(facts_fingerprint ~ '^[0-9a-f]{64}$'),snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),confirmado_por uuid NOT NULL REFERENCES public.utilizadores(id),confirmado_em timestamptz NOT NULL DEFAULT now(),request_id uuid NOT NULL,reason text,UNIQUE(empresa_id,obra_id,fornecedor_id,competencia,revision),UNIQUE(empresa_id,confirmado_por,request_id)
);ALTER TABLE public.folha_externos_confirmacoes ENABLE ROW LEVEL SECURITY;REVOKE ALL ON public.folha_externos_confirmacoes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION folha_privado.externo_mes_v3(w uuid,provider uuid,m date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $month$
DECLARE u public.utilizadores;r jsonb;hash text;
BEGIN
 u:=folha_privado.ator();IF w IS NULL OR provider IS NULL OR m IS NULL OR NOT isfinite(m) OR extract(day FROM m)<>1 THEN RAISE EXCEPTION 'MONTH_REQUIRED';END IF;
 r:=public.fn_folha_relatorio_horas_v3(w,m,(m+interval '1 month')::date-1,'external',provider);
 hash:=encode(sha256(convert_to(jsonb_build_array('external_month_v3',u.empresa_id,w,provider,m,r->'records')::text,'UTF8')),'hex');RETURN r||jsonb_build_object('facts_fingerprint',hash,'month',m,'provider_id',provider);
END $month$;
CREATE FUNCTION folha_privado.externo_confirmacao_guardar_v3() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $guard$
DECLARE u public.utilizadores;c public.folha_externos_confirmacoes;r jsonb;
BEGIN
 IF current_user<>'postgres' OR TG_OP<>'INSERT' THEN RAISE EXCEPTION 'EXTERNAL_CONFIRMATION_PROTECTED' USING ERRCODE='42501';END IF;u:=folha_privado.ator();
 IF u.funcao<>'diretor_obra' OR NEW.empresa_id<>u.empresa_id OR NEW.confirmado_por<>u.id OR NEW.confirmado_em IS DISTINCT FROM now() THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=NEW.obra_id AND utilizador_id=u.id AND papel='diretor_obra';IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;
 SELECT * INTO c FROM public.folha_externos_confirmacoes WHERE empresa_id=u.empresa_id AND obra_id=NEW.obra_id AND fornecedor_id=NEW.fornecedor_id AND competencia=NEW.competencia ORDER BY revision DESC LIMIT 1;
 IF NEW.revision<>coalesce(c.revision,0)+1 THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001';END IF;
 r:=folha_privado.externo_mes_v3(NEW.obra_id,NEW.fornecedor_id,NEW.competencia);IF NEW.snapshot IS DISTINCT FROM r OR NEW.facts_fingerprint IS DISTINCT FROM r->>'facts_fingerprint' THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001';END IF;RETURN NEW;
END $guard$;
CREATE TRIGGER folha_externos_confirmacao_guardar BEFORE INSERT OR UPDATE OR DELETE ON public.folha_externos_confirmacoes FOR EACH ROW EXECUTE FUNCTION folha_privado.externo_confirmacao_guardar_v3();
CREATE FUNCTION public.fn_folha_externos_confirmar_v3(p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $confirm$
DECLARE u public.utilizadores;req uuid:=(p_dados->>'request_id')::uuid;w uuid:=(p_dados->>'work_id')::uuid;provider uuid:=(p_dados->>'provider_id')::uuid;m date:=(p_dados->>'month')::date;old public.folha_externos_confirmacoes;n public.folha_externos_confirmacoes;r jsonb;payload jsonb;token text;result jsonb;op folha_privado.operacoes;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001';END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);u:=folha_privado.ator();IF (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) OR (p_dados ? 'company_id' AND (p_dados->>'company_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'TENANT_HINT_MISMATCH' USING ERRCODE='42501';END IF;PERFORM 1 FROM public.utilizadores WHERE id=u.id FOR SHARE;u:=folha_privado.ator();
 IF u.funcao<>'diretor_obra' THEN RAISE EXCEPTION 'PERMISSION_DENIED: confirmação do Diretor' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id FOR SHARE;IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=w AND utilizador_id=u.id AND papel='diretor_obra' FOR SHARE;IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;
 IF req IS NULL OR p_confirmar IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 3 OR provider IS NULL OR m IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_dados) x WHERE x NOT IN('version','request_id','work_id','provider_id','month','expected_revision','reason')) THEN RAISE EXCEPTION 'UNKNOWN_FIELD';END IF;
 payload:=jsonb_build_object('action','external_confirm','data',p_dados);SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';END IF;IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',op.token);END IF;IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;RETURN op.resultado;END IF;
 PERFORM 1 FROM public.folha_registos f JOIN public.folha_externos e ON e.id=f.externo_id WHERE f.empresa_id=u.empresa_id AND f.obra_id=w AND e.fornecedor_id=provider AND f.data>=m AND f.data<(m+interval '1 month')::date FOR SHARE OF f;
 SELECT * INTO old FROM public.folha_externos_confirmacoes WHERE empresa_id=u.empresa_id AND obra_id=w AND fornecedor_id=provider AND competencia=m ORDER BY revision DESC LIMIT 1 FOR UPDATE;
 IF (p_dados->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001';END IF;
 IF old.id IS NOT NULL AND nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED';END IF;
 r:=folha_privado.externo_mes_v3(w,provider,m);IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'records') x WHERE (x->>'open')::boolean) THEN RAISE EXCEPTION 'EXTERNAL_OPEN_INTERVALS';END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('actor',u.id,'tenant',u.empresa_id,'payload',payload,'before',to_jsonb(old),'source',r)::text,'UTF8')),'hex');IF NOT p_confirmar THEN RETURN jsonb_build_object('version',3,'committed',false,'versao',token,'preview',r);END IF;IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001';END IF;
 INSERT INTO public.folha_externos_confirmacoes(empresa_id,obra_id,fornecedor_id,competencia,revision,facts_fingerprint,snapshot,confirmado_por,request_id,reason) VALUES(u.empresa_id,w,provider,m,coalesce(old.revision,0)+1,r->>'facts_fingerprint',r,u.id,req,p_dados->>'reason') RETURNING * INTO n;
 result:=jsonb_build_object('version',3,'committed',true,'request_id',req,'confirmation_id',n.id,'revision',n.revision,'facts_fingerprint',n.facts_fingerprint);INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $confirm$;
CREATE FUNCTION public.fn_folha_externos_excel_contexto_v3(p_obra_id uuid,p_fornecedor_id uuid,p_competencia date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $export$
DECLARE u public.utilizadores;c public.folha_externos_confirmacoes;r jsonb;
BEGIN
 u:=folha_privado.ator();r:=folha_privado.externo_mes_v3(p_obra_id,p_fornecedor_id,p_competencia);
 SELECT * INTO c FROM public.folha_externos_confirmacoes WHERE empresa_id=u.empresa_id AND obra_id=p_obra_id AND fornecedor_id=p_fornecedor_id AND competencia=p_competencia ORDER BY revision DESC LIMIT 1;
 IF c.id IS NULL OR c.facts_fingerprint IS DISTINCT FROM r->>'facts_fingerprint' THEN RAISE EXCEPTION 'EXTERNAL_CONFIRMATION_REQUIRED: confirmar a revisão atual';END IF;
 RETURN jsonb_build_object('version',3,'server_authorized',true,'export_format','xlsx','confirmed_by_role','diretor_obra','confirmation_id',c.id,'revision',c.revision,'facts_fingerprint',c.facts_fingerprint,'confirmed_by',c.confirmado_por,'confirmed_at',c.confirmado_em,'report',r,'financial_effect',false);
END $export$;
REVOKE ALL ON FUNCTION folha_privado.externo_mes_v3(uuid,uuid,date),folha_privado.externo_confirmacao_guardar_v3(),public.fn_folha_externos_confirmar_v3(jsonb,boolean,text),public.fn_folha_externos_excel_contexto_v3(uuid,uuid,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_externos_confirmar_v3(jsonb,boolean,text),public.fn_folha_externos_excel_contexto_v3(uuid,uuid,date) TO authenticated;
