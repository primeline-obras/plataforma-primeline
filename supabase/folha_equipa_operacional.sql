-- Prepared locally under explicit task section 25. Never run at app startup.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos,public.colaboradores,public.obras,public.utilizadores,public.folha_registos,public.folha_externos_dias,public.ausencias,public.ponto_pessoal_obra IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.ponto_pessoal_obra'::regclass AND t.tgname='trg_01_folha_legacy_closed' AND t.tgfoid=to_regprocedure('folha_privado.legacy_closed()') AND t.tgtype=62 AND t.tgenabled IN('O','A')) THEN RAISE EXCEPTION 'LEGACY_CUTOVER_UNCONFIRMED'; END IF;
 IF to_regclass('primeline_equipa_backup.funcoes') IS NULL THEN RAISE EXCEPTION 'BACKUP_REQUIRED'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.local(uuid,uuid,boolean)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '981dc2ae8f873aef0138520a13c5ff476925663ef75109d5d157c2038fad310b' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.local'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.linha(uuid,uuid,date,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '10ef71c91baf7490b5707597a0f8ce95b90633d1a7188f3e9513fa5594b97cbc' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.linha'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.save(jsonb,uuid,date,uuid,boolean)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM 'df3886df93ab0b696980f05699cb1f04e412622e2233da84ededf219f1e8fac2' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.save'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.normal(uuid,uuid,date)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM 'b074005aa19185b162c09ba957e4b2e4faca4723e6a81247b2d10e7953b5b03a' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.normal'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_contexto_v2(date,uuid)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '3a7eb0e02b9f07ebd7ccc8d7b6d826cb507d447171b10b2fbbd46edcde5954cf' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_contexto_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_pessoas_v2(date,uuid)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '845c9e8761b2f0625241a9f0571ca9cf0f48f1f1bdf7de7acfa0d042cbb411f6' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_pessoas_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_operar_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '9571c6e063d0f65edbd2a83d3035bcb0b581c711f33f65ac200da38ebc5d87de' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_operar_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '5c9aba5e347726b6a0d284c3d661aa5fbdc9b9f24d251eaa95b978d3251a06c6' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_gestao_v2'; END IF;

END $$;
DO $$ DECLARE b record; actual jsonb; BEGIN FOR b IN SELECT * FROM primeline_equipa_backup.funcoes LOOP
 IF pg_get_functiondef(to_regprocedure(b.assinatura)) IS DISTINCT FROM b.definicao THEN RAISE EXCEPTION 'BACKUP_FUNCTION_DRIFT: %',b.assinatura; END IF;
 END LOOP; FOR b IN SELECT * FROM primeline_equipa_backup.legado LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',b.tabela) INTO actual;
 IF actual IS DISTINCT FROM b.linhas THEN RAISE EXCEPTION 'BACKUP_DATA_DRIFT: %',b.tabela; END IF;
 END LOOP; END $$;
-- Local rollout source. Combined migration includes reviewed replacements of V2 readers/writers.
CREATE TABLE public.quadro_equipa_permanencias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id), obra_id uuid NOT NULL REFERENCES public.obras(id),
 inicio date NOT NULL, fim date, criado_por uuid NOT NULL REFERENCES public.utilizadores(id),
 criado_em timestamptz NOT NULL DEFAULT now(), encerrado_por uuid REFERENCES public.utilizadores(id),
 request_id uuid NOT NULL, CHECK(fim IS NULL OR fim>=inicio)
);
CREATE INDEX quadro_equipa_validade ON public.quadro_equipa_permanencias(colaborador_id,inicio,fim);
CREATE INDEX quadro_equipa_obra ON public.quadro_equipa_permanencias(obra_id,inicio,fim);
CREATE TABLE folha_privado.equipa_revisoes(colaborador_id uuid PRIMARY KEY REFERENCES public.colaboradores(id),revision integer NOT NULL CHECK(revision>0));
ALTER TABLE folha_privado.equipa_revisoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ADD COLUMN delegacao text CHECK(delegacao IN('lisboa','algarve'));
ALTER TABLE public.obras ADD COLUMN delegacao text CHECK(delegacao IN('lisboa','algarve'));
ALTER TABLE public.utilizadores ADD COLUMN delegacao text CHECK(delegacao IN('lisboa','algarve'));
ALTER TABLE public.folha_externos_dias ADD COLUMN funcao text CHECK(funcao IN('pedreiro','servente'));
-- NULL only preserves existing external facts; new daily records must supply role.
CREATE FUNCTION folha_privado.elegivel_equipa(p uuid,d date) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=(folha_privado.ator()).empresa_id
 AND lower(btrim(c.funcao)) IN('pedreiro','servente') AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d))
$$;
CREATE FUNCTION folha_privado.guardar_permanencia() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(61001,1);
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'TEAM_HISTORY_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND (NEW.id,NEW.empresa_id,NEW.colaborador_id,NEW.obra_id,NEW.inicio,NEW.criado_por,NEW.criado_em,NEW.request_id)
 IS DISTINCT FROM (OLD.id,OLD.empresa_id,OLD.colaborador_id,OLD.obra_id,OLD.inicio,OLD.criado_por,OLD.criado_em,OLD.request_id)
 THEN RAISE EXCEPTION 'TEAM_HISTORY_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND OLD.fim IS NOT NULL THEN RAISE EXCEPTION 'TEAM_HISTORY_IMMUTABLE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.obras o ON o.id=NEW.obra_id
 WHERE c.id=NEW.colaborador_id AND c.empresa_id=NEW.empresa_id AND o.empresa_id=NEW.empresa_id)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: tenant da permanência' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=NEW.colaborador_id AND e.id<>NEW.id
 AND daterange(e.inicio,e.fim,'[)')&&daterange(NEW.inicio,NEW.fim,'[)')) THEN RAISE EXCEPTION 'TEAM_OVERLAP'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER equipa_integridade BEFORE INSERT OR UPDATE OR DELETE ON public.quadro_equipa_permanencias
FOR EACH ROW EXECUTE FUNCTION folha_privado.guardar_permanencia();
ALTER TABLE public.quadro_equipa_permanencias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quadro_equipa_permanencias,folha_privado.equipa_revisoes FROM PUBLIC,anon,authenticated,service_role;
-- No direct DML. Existing operational RPCs own the authorization boundary.
CREATE OR REPLACE FUNCTION public.fn_quadro_resolver_data(p_data date)
RETURNS SETOF public.quadro_pessoal_alocacao LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT q.* FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=(folha_privado.ator()).empresa_id AND q.data=p_data
 AND (NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=q.colaborador_id AND e.inicio<=p_data)
 OR EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=q.colaborador_id AND e.obra_id=q.obra_id AND e.inicio<=p_data AND (e.fim IS NULL OR e.fim>p_data)))
 UNION ALL
 SELECT (jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,jsonb_build_object(
 'id',md5(e.id::text||':'||p_data::text)::uuid,'colaborador_id',e.colaborador_id,'obra_id',e.obra_id,'data',p_data,'semana_inicio',date_trunc('week',p_data)::date,
 'periodo','dia_inteiro','tipo_alocacao','obra','criado_por',e.criado_por,'criado_em',e.criado_em))).*
 FROM public.quadro_equipa_permanencias e JOIN public.colaboradores c ON c.id=e.colaborador_id
 WHERE e.empresa_id=(folha_privado.ator()).empresa_id AND e.inicio<=p_data AND (e.fim IS NULL OR e.fim>p_data)
 AND c.data_admissao<=p_data AND (c.data_saida IS NULL OR c.data_saida>p_data)
 AND NOT EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=e.colaborador_id AND q.data=p_data AND q.obra_id=e.obra_id)
$$;
-- Direct daily edits must not modify/delete virtual membership rows or silently create competing destinations.
CREATE FUNCTION folha_privado.proteger_alocacao_persistente() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p uuid; d date;
BEGIN
 PERFORM pg_advisory_xact_lock(61001,1);
 p:=CASE WHEN TG_OP='DELETE' THEN OLD.colaborador_id ELSE NEW.colaborador_id END;
 d:=CASE WHEN TG_OP='DELETE' THEN OLD.data ELSE NEW.data END;
 IF EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=p AND e.inicio<=d AND (e.fim IS NULL OR e.fim>d))
 OR TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias e WHERE e.colaborador_id=OLD.colaborador_id AND e.inicio<=OLD.data AND (e.fim IS NULL OR e.fim>OLD.data))
 THEN RAISE EXCEPTION 'TEAM_PERSISTENT: use adicionar/retirar/transferir na Folha; não alterar alocações diárias'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER trg_01_equipa_alocacao BEFORE INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao
FOR EACH ROW EXECUTE FUNCTION folha_privado.proteger_alocacao_persistente();
CREATE FUNCTION public.fn_equipa_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid; d date; req uuid; item jsonb; p uuid; current_team public.quadro_equipa_permanencias;
 rev integer; before jsonb:='[]'; after jsonb:='[]'; token text; payload jsonb; op folha_privado.operacoes; result jsonb; keys jsonb:='[]'; new_id uuid;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 SELECT * INTO u FROM public.utilizadores WHERE id=(folha_privado.ator()).id AND ativo FOR SHARE; w:=(p_dados->>'work_id')::uuid; d:=(p_dados->>'date')::date; req:=(p_dados->>'request_id')::uuid;
 PERFORM folha_privado.obra(w,true);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF req IS NULL OR d IS NULL OR w IS NULL OR p_confirmar IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2
 OR p_acao IS NULL OR p_acao NOT IN('team_add','team_remove','team_transfer') OR jsonb_typeof(p_dados->'people') IS DISTINCT FROM 'array'
 OR jsonb_array_length(p_dados->'people') NOT BETWEEN 1 AND 200
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'people') x GROUP BY x->>'person_id' HAVING count(*)>1)
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: equipa'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id AND situacao='em_curso') THEN RAISE EXCEPTION 'WORK_UNAVAILABLE'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') LOOP
   IF NOT folha_privado.elegivel_equipa((item->>'person_id')::uuid,d) THEN RAISE EXCEPTION 'PERMISSION_DENIED: elegibilidade' USING ERRCODE='42501'; END IF;
  END LOOP;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token,'summary','Operação já registada.'); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'person_id' LOOP
  p:=(item->>'person_id')::uuid;
  PERFORM 1 FROM public.colaboradores WHERE id=p FOR UPDATE;
  IF NOT folha_privado.elegivel_equipa(p,d) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas Pedreiro/Servente interno ativo' USING ERRCODE='42501'; END IF;
  SELECT coalesce((SELECT revision FROM folha_privado.equipa_revisoes WHERE colaborador_id=p),0) INTO rev;
  IF (item->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
  SELECT * INTO current_team FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d) FOR UPDATE;
  IF p_acao='team_add' AND (current_team.id IS NOT NULL OR EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio>d)) THEN RAISE EXCEPTION 'TEAM_CONFLICT'; END IF;
  IF p_acao IN('team_remove','team_transfer') AND (current_team.id IS NULL OR current_team.obra_id IS DISTINCT FROM (CASE WHEN p_acao='team_remove' THEN w ELSE (item->>'source_work_id')::uuid END)) THEN RAISE EXCEPTION 'STALE_TEAM'; END IF;
  IF p_acao='team_transfer' THEN
   IF EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio>d) THEN RAISE EXCEPTION 'TEAM_FUTURE_CONFLICT'; END IF;
   PERFORM folha_privado.obra(current_team.obra_id,true);
   IF current_team.obra_id=w THEN RAISE EXCEPTION 'TEAM_SAME_WORK'; END IF;
  END IF;
  IF p_acao<>'team_remove' AND EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=d
   AND (q.tipo_alocacao<>'obra' OR q.obra_id IS DISTINCT FROM w AND NOT (p_acao='team_transfer' AND q.obra_id=current_team.obra_id))) THEN RAISE EXCEPTION 'SCHEDULED_ALLOCATION_CONFLICT: rever alocações explícitas'; END IF;
  IF p_acao<>'team_remove' AND EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data>=d AND obra_id IS DISTINCT FROM w) THEN RAISE EXCEPTION 'FACT_HISTORY_CONFLICT: rever data efetiva'; END IF;
  IF EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT'; END IF;
  before:=before||jsonb_build_array(jsonb_build_object('person_id',p,'revision',rev,'membership',to_jsonb(current_team)));
  after:=after||jsonb_build_array(jsonb_build_object('person_id',p,'revision',rev+1,'work_id',CASE WHEN p_acao='team_remove' THEN NULL ELSE w END,'date',d));
 END LOOP;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',before,'after',after)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after,
 'summary',format('%s: %s pessoas a partir de %s. O histórico é preservado; a permanência continua até retirada/transferência. Confirmar?',CASE p_acao WHEN 'team_add' THEN 'Adicionar à equipa' WHEN 'team_remove' THEN 'Retirar da equipa' ELSE 'Transferir equipa' END,jsonb_array_length(after),d)); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(before) LOOP
  p:=(item->>'person_id')::uuid;
  IF p_acao IN('team_remove','team_transfer') THEN
   UPDATE public.quadro_equipa_permanencias SET fim=d,encerrado_por=u.id WHERE id=(item->'membership'->>'id')::uuid;
  END IF;
  IF p_acao<>'team_remove' THEN
   INSERT INTO public.quadro_equipa_permanencias(empresa_id,colaborador_id,obra_id,inicio,criado_por,request_id)
   VALUES(u.empresa_id,p,w,d,u.id,req) RETURNING id INTO new_id;
  END IF;
  INSERT INTO folha_privado.equipa_revisoes VALUES(p,(item->>'revision')::integer+1)
  ON CONFLICT(colaborador_id) DO UPDATE SET revision=excluded.revision;
  INSERT INTO public.quadro_pessoal_movimentos(empresa_id,colaborador_id,data,periodo,acao,obra_origem_id,obra_destino_id,alterado_por,perfil_autor,antes,depois,origem_operacao,request_id)
  VALUES(u.empresa_id,p,d,'dia_inteiro',CASE WHEN p_acao='team_remove' THEN 'removida' WHEN p_acao='team_transfer' THEN 'movida' ELSE 'adicionada' END,
  (item->'membership'->>'obra_id')::uuid,CASE WHEN p_acao='team_remove' THEN NULL ELSE w END,u.id,u.funcao,item,
  jsonb_build_object('request_id',req,'membership_id',new_id,'effective_date',d,'action',p_acao),'folha_v2',req);
  IF p_acao<>'team_remove' THEN
   INSERT INTO public.quadro_escrita_interna VALUES(txid_current(),p,d,u.id,'folha_v2',req);
   PERFORM public.fn_quadro_notificar_controlado_v1(p,d,(item->'membership'->>'obra_id')::uuid,w,new_id);
   DELETE FROM public.quadro_escrita_interna WHERE transacao=txid_current() AND colaborador_id=p AND data=d;
  END IF;
  INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
  VALUES(u.empresa_id,w,'obra',p,'primeline',d,CASE p_acao WHEN 'team_remove' THEN 'remove_from_day' WHEN 'team_transfer' THEN 'transfer' ELSE 'allocate' END,item,
  jsonb_build_object('action',p_acao,'effective_date',d,'work_id',CASE WHEN p_acao='team_remove' THEN NULL ELSE w END),(item->>'revision')::integer+1,u.id,req,p_dados->>'reason');
  keys:=keys||jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p,'work_id',w,'date',d));
 END LOOP;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys,'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;
CREATE FUNCTION public.fn_folha_ferias_mapa_v2(p_inicio date,p_fim date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 u:=folha_privado.ator();
 IF u.funcao<>'encarregado' AND NOT folha_privado.admin() THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>366 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo'; END IF;
 RETURN jsonb_build_object('version',2,'people',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'funcao',c.funcao) ORDER BY c.nome)
 FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND c.data_admissao<=p_fim AND (c.data_saida IS NULL OR c.data_saida>p_inicio)),'[]'),
 'vacations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'colaborador_id',a.colaborador_id,'data',a.data,'tipo','ferias','estado',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE c.empresa_id=u.empresa_id AND a.tipo='ferias' AND a.data BETWEEN p_inicio AND p_fim),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.fn_equipa_operar_v2(text,jsonb,boolean,text),public.fn_folha_ferias_mapa_v2(date,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_equipa_operar_v2(text,jsonb,boolean,text),public.fn_folha_ferias_mapa_v2(date,date) TO authenticated;

CREATE OR REPLACE FUNCTION folha_privado.linha(p uuid,w uuid,d date,k text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; nome text; papel text; fornecedor text; s public.folha_registos;
 a jsonb; expected integer; conf text; rev integer; ids jsonb; period text; legacy boolean:=false;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.local(p,w);
 IF k='primeline' THEN
  SELECT c.nome,c.funcao INTO nome,papel FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',x.id,'data',x.data,'tipo',x.tipo,'estado',x.estado) INTO a FROM public.ausencias x WHERE x.colaborador_id=p AND x.data=d ORDER BY x.criado_em DESC,x.id LIMIT 1;
  legacy:=EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND obra_id IS NOT DISTINCT FROM w AND data=d AND empresa_id=u.empresa_id);
  -- The existing writer guard covers the whole person/day. Expose only its block,
  -- never the other work or its legacy details, when the selected fact differs.
  IF NOT legacy AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data=d) THEN conf:='LEGACY_WRITER_BLOCKED'; END IF;
  SELECT coalesce(jsonb_agg(q.id ORDER BY q.id),'[]'),CASE WHEN count(DISTINCT q.periodo)>1 THEN 'dia_inteiro' ELSE min(q.periodo) END INTO ids,period FROM public.fn_quadro_resolver_data(d) q WHERE q.colaborador_id=p AND q.obra_id=w;
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q JOIN public.quadro_pessoal_alocacao other ON q.colaborador_id=other.colaborador_id AND q.data=other.data AND q.id<other.id
   WHERE q.colaborador_id=p AND q.data=d AND (q.periodo='dia_inteiro' OR other.periodo='dia_inteiro' OR q.periodo=other.periodo))
  THEN conf:='ALLOCATION_CONFLICT'; END IF;
  SELECT coalesce(revisao,0) INTO rev FROM public.quadro_dias_revisoes WHERE colaborador_id=p AND data=d;
 ELSE
  SELECT e.nome,f.nome INTO nome,fornecedor FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id
   WHERE e.id=p AND e.empresa_id=u.empresa_id AND f.empresa_id=u.empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT * INTO s FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND (CASE WHEN k='primeline' THEN colaborador_id=p ELSE externo_id=p END);
 IF legacy AND s.id IS NOT NULL THEN conf:='LEGACY_CONFLICT'; END IF;
 SELECT CASE WHEN period IN('manha','tarde') THEN
  (SELECT sum((extract(epoch from ((x->>'end')::time-(x->>'start')::time))/60)::integer) FROM jsonb_array_elements(h.intervals) x WHERE x->>'period'=period)
 ELSE h.expected_minutes END INTO expected FROM public.folha_horarios h WHERE h.obra_id=w;
 IF w IS NULL THEN
  expected:=coalesce((SELECT office_expected_minutes FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),480);
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao WHERE colaborador_id=p AND data=d AND obra_id IS NOT NULL) THEN conf:='ALLOCATION_CONFLICT'; END IF;
 END IF;
 IF s.id IS NOT NULL THEN expected:=s.expected_minutes; END IF;
 IF k='external' THEN expected:=NULL; SELECT funcao INTO papel FROM public.folha_externos_dias WHERE externo_id=p AND obra_id=w AND data=d; END IF;
 RETURN jsonb_build_object('tipo_local',CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,'person_id',p,'name',nome,'role',papel,'provider_name',fornecedor,
  'sheet',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object('id',s.id,'intervals',s.intervals,'note',s.note,'state',s.estado) END,
  'absence',a,'legacy',legacy,'conflict',conf,'special_day',s.special_day,'special_reviewed',s.special_reviewed_at IS NOT NULL,'special_review_pending',s.special_day AND s.special_reviewed_at IS NULL,'revision',coalesce(s.revision,0),'allocation_revision',coalesce(rev,0),
  'allocation_ids',coalesce(ids,'[]'),'period',coalesce(period,'dia_inteiro'),'expected_minutes',expected,
  'team_revision',coalesce((SELECT revision FROM folha_privado.equipa_revisoes WHERE colaborador_id=p),0),
 'delegation',(SELECT delegacao FROM public.colaboradores WHERE id=p),
 'membership_id',(SELECT id FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)),
 'can_remove',EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)) AND w IS NOT NULL AND NOT legacy AND conf IS NULL AND s.id IS NULL AND a IS NULL AND NOT EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d)
   AND EXISTS(SELECT 1 FROM public.obras WHERE id=w AND situacao='em_curso')
   AND EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d))
   AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),
  'overtime',CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('estado',coalesce((SELECT h.estado FROM public.folha_he h WHERE h.folha_id=s.id AND h.folha_revision=s.revision AND h.estado<>'superseded'),CASE WHEN s.special_day AND s.special_reviewed_at IS NULL AND s.estado<>'regularization' THEN 'pending_rule' ELSE 'none' END)) END,
  'can_write',NOT legacy AND conf IS NULL AND d<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND (d=(now() AT TIME ZONE 'Europe/Lisbon')::date OR folha_privado.adm_operacional() OR d>=(now() AT TIME ZONE 'Europe/Lisbon')::date-1) AND (w IS NULL OR folha_privado.admin() OR u.funcao='encarregado' OR EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND utilizador_id=u.id AND u.funcao IN('diretor_obra','adjunto','preparador'))) AND ((k='external' AND EXISTS(SELECT 1 FROM public.folha_externos WHERE id=p AND empresa_id=u.empresa_id AND ativo)) OR EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d))));
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_contexto_v2(p_data date,p_obra_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; works jsonb; rows jsonb:='[]'; ext jsonb:='[]'; sched jsonb; providers jsonb:='[]'; x record; special boolean;
 office boolean:=false; self_id uuid; summary jsonb; r jsonb; registered integer:=0; opened integer:=0; pending integer:=0; total integer; worked integer; status text;
BEGIN
 u:=folha_privado.ator();
 SELECT min(c.id::text)::uuid INTO self_id FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id HAVING count(*)=1;
 office:=folha_privado.admin() OR (u.funcao IN('diretor_obra','adjunto','preparador') AND self_id IS NOT NULL);
 IF p_data IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: data'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.numero,'name',o.nome) ORDER BY o.numero),'[]') INTO works
 FROM public.obras o WHERE o.empresa_id=u.empresa_id AND
 (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=o.id AND r.utilizador_id=u.id AND r.papel=u.funcao AND u.funcao IN('encarregado','diretor_obra','adjunto','preparador')));
 IF p_obra_id IS NOT NULL THEN
  PERFORM folha_privado.local(self_id,p_obra_id);
  FOR x IN SELECT c.id colaborador_id FROM public.colaboradores c WHERE c.id=self_id AND u.funcao IN('diretor_obra','adjunto','preparador')
 UNION SELECT DISTINCT q.colaborador_id FROM public.fn_quadro_resolver_data(p_data) q JOIN public.colaboradores c ON c.id=q.colaborador_id AND c.empresa_id=u.empresa_id WHERE q.obra_id=p_obra_id AND q.data=p_data
   UNION SELECT f.colaborador_id FROM public.folha_registos f JOIN public.colaboradores c ON c.id=f.colaborador_id AND c.empresa_id=u.empresa_id WHERE f.obra_id=p_obra_id AND f.data=p_data AND f.empresa_id=u.empresa_id
   UNION SELECT h.colaborador_id FROM public.ponto_pessoal_obra h JOIN public.colaboradores c ON c.id=h.colaborador_id AND c.empresa_id=u.empresa_id WHERE h.obra_id=p_obra_id AND h.data=p_data AND h.empresa_id=u.empresa_id LOOP
   IF EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=x.colaborador_id AND (lower(btrim(c.funcao)) IN('pedreiro','servente') OR c.utilizador_id=u.id)) THEN
 rows:=rows||jsonb_build_array(folha_privado.linha(x.colaborador_id,p_obra_id,p_data,'primeline')); END IF;
  END LOOP;
  FOR x IN SELECT e.id FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id
   AND (EXISTS(SELECT 1 FROM public.folha_externos_dias ed WHERE ed.externo_id=e.id AND ed.obra_id=p_obra_id AND ed.data=p_data)
   OR EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.externo_id=e.id AND f.data=p_data AND f.obra_id=p_obra_id)) LOOP
   ext:=ext||jsonb_build_array(folha_privado.linha(x.id,p_obra_id,p_data,'external'));
  END LOOP;
  SELECT jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes,'revision',h.revision) INTO sched FROM public.folha_horarios h WHERE h.obra_id=p_obra_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.nome)),'[]') INTO providers FROM public.fornecedores f
   WHERE f.empresa_id=u.empresa_id AND (folha_privado.admin() OR u.funcao='encarregado') AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=p_obra_id));
 ELSIF office THEN
  PERFORM folha_privado.local(self_id,NULL);
  FOR x IN SELECT c.id colaborador_id FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND (c.id=self_id OR folha_privado.admin() AND (EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=c.id AND q.data=p_data AND q.tipo_alocacao='escritorio') OR EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=c.id AND f.obra_id IS NULL AND f.data=p_data))) LOOP
   rows:=rows||jsonb_build_array(folha_privado.linha(x.colaborador_id,NULL,p_data,'primeline'));
  END LOOP;
  sched:=jsonb_build_object('intervals','[]'::jsonb,'expected_minutes',coalesce((SELECT office_expected_minutes FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),480));
 END IF;
 special:=extract(isodow FROM p_data)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND p_data=ANY(holiday_dates));
 FOR r IN SELECT value FROM jsonb_array_elements(rows||ext) LOOP
  IF r->'sheet'<>'null'::jsonb THEN status:=r->'sheet'->>'state';
  ELSIF r->>'conflict' IS NOT NULL THEN status:='regularization';
  ELSIF r->'absence'<>'null'::jsonb THEN status:=CASE WHEN r->'sheet'<>'null'::jsonb THEN 'regularization' WHEN r->'absence'->>'estado'='ausente_pendente' THEN 'absence_pending' ELSE 'absence' END;
  ELSIF (r->>'legacy')::boolean THEN status:='legacy';
  ELSIF r->'sheet'='null'::jsonb THEN status:='none';
  ELSIF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'sheet'->'intervals') i WHERE i->>'end' IS NULL) THEN status:='open';
  ELSE
   SELECT sum((extract(epoch FROM ((i->>'end')::time-(i->>'start')::time))/60)::integer) INTO worked FROM jsonb_array_elements(r->'sheet'->'intervals') i;
   status:=CASE WHEN r->>'expected_minutes' IS NULL THEN 'regularization' WHEN worked<(r->>'expected_minutes')::integer THEN 'missing' ELSE 'registered' END;
  END IF;
  registered:=registered+CASE WHEN status='registered' THEN 1 ELSE 0 END; opened:=opened+CASE WHEN status='open' THEN 1 ELSE 0 END;
  pending:=pending+CASE WHEN status IN('registered','absence','legacy') AND NOT coalesce((r->>'special_review_pending')::boolean,false) THEN 0 ELSE 1 END;
 END LOOP;
 summary:=jsonb_build_object('people',jsonb_array_length(rows||ext),'registered',registered,'open',opened,'pending',pending,'complete',jsonb_array_length(rows||ext)>0 AND pending=0);
 RETURN jsonb_build_object('version',2,'date',p_data,'work_id',p_obra_id,'works',works,'rows',rows,'external_rows',ext,
  'tipo_local',CASE WHEN p_obra_id IS NULL THEN 'escritorio' ELSE 'obra' END,'office_available',office,'self_person_id',self_id,'correction_days',1,'admin',folha_privado.admin(),'summary',summary,'schedule',sched,'special_day',special,'providers',providers,
  'external_people',coalesce((SELECT jsonb_agg(jsonb_build_object('id',e.id,'name',e.nome,'provider_id',e.fornecedor_id)) FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id AND e.ativo AND (folha_privado.admin() OR u.funcao='encarregado') AND EXISTS(SELECT 1 FROM public.fornecedores f WHERE f.id=e.fornecedor_id AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=p_obra_id)))
   AND NOT EXISTS(SELECT 1 FROM public.folha_externos_dias ed WHERE ed.externo_id=e.id AND ed.data=p_data AND ed.obra_id=p_obra_id)),'[]'),
  'team_contract',1,'delegation',coalesce((SELECT delegacao FROM public.obras WHERE id=p_obra_id),u.delegacao),'management',folha_privado.admin() OR p_obra_id IS NOT NULL AND u.funcao IN('diretor_obra','adjunto'),
  'calendar_verified',coalesce((SELECT calendar_complete AND extract(year FROM p_data)::integer=ANY(calendar_validated_years) FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),false),
  'overtime_generation',CASE WHEN EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND overtime_enabled AND calendar_complete AND extract(year FROM p_data)::integer=ANY(calendar_validated_years)) THEN 'enabled' ELSE 'disabled_pending_compatibility' END,
  'permissions',jsonb_build_object('write',CASE WHEN p_obra_id IS NULL THEN office ELSE folha_privado.admin() OR u.funcao='encarregado' OR (u.funcao IN('diretor_obra','adjunto','preparador') AND self_id IS NOT NULL) END,'allocation_write',p_obra_id IS NOT NULL AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),'external_write',p_obra_id IS NOT NULL AND (folha_privado.admin() OR u.funcao='encarregado')));
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_pessoas_v2(p_data date,p_obra_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; people jsonb;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.obra(p_obra_id);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: alocação' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('person_id',c.id,'name',c.nome,
 'role',c.funcao,'delegation',c.delegacao,'team_revision',coalesce(er.revision,0),
 'current_work',CASE WHEN q.id IS NULL THEN NULL ELSE jsonb_build_object('id',q.obra_id,'type',q.tipo_alocacao,'label',CASE WHEN q.obra_id IS NULL THEN q.tipo_alocacao ELSE 'Obra '||o.numero END) END,
 'allocation_revision',coalesce(r.revisao,0),'can_allocate',(q.id IS NULL OR q.obra_id=p_obra_id AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND inicio<=p_data AND (fim IS NULL OR fim>p_data))) AND NOT a.blocked,
 'can_transfer',EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND inicio<=p_data AND (fim IS NULL OR fim>p_data)) AND (folha_privado.admin() OR public.fn_quadro_minha_obra_v1(q.obra_id)) AND q.id IS NOT NULL AND q.tipo_alocacao='obra' AND o.empresa_id=u.empresa_id AND NOT a.blocked)),'[]') INTO people
 FROM public.colaboradores c LEFT JOIN folha_privado.equipa_revisoes er ON er.colaborador_id=c.id
 LEFT JOIN LATERAL(SELECT * FROM public.fn_quadro_resolver_data(p_data) WHERE colaborador_id=c.id ORDER BY id LIMIT 1) q ON true
 LEFT JOIN public.obras o ON o.id=q.obra_id LEFT JOIN public.quadro_dias_revisoes r ON r.colaborador_id=c.id AND r.data=p_data
 CROSS JOIN LATERAL(SELECT EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=c.id AND data=p_data)
 OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=c.id AND data=p_data)
 OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=c.id AND data=p_data)
 OR (SELECT count(*) FROM public.quadro_pessoal_alocacao WHERE colaborador_id=c.id AND data=p_data)>1 blocked) a
 WHERE folha_privado.elegivel_equipa(c.id,p_data) AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND obra_id=p_obra_id AND inicio<=p_data AND (fim IS NULL OR fim>p_data));
 RETURN jsonb_build_object('version',2,'people',people);
END $$;

CREATE OR REPLACE FUNCTION folha_privado.save(p jsonb,w uuid,d date,req uuid,confirmar boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
 row jsonb; f jsonb; state text; expected integer; window_days integer; special boolean; result public.folha_registos;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.local(person,w,true); PERFORM folha_privado.lock_dia(person,d);
 IF p->'key'->>'work_id' IS DISTINCT FROM w::text OR p->'key'->>'date' IS DISTINCT FROM d::text OR kind IS NULL OR kind NOT IN('primeline','external')
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: chave'; END IF;
 row:=folha_privado.linha(person,w,d,kind);
 IF kind='primeline' AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'LEGACY_CONFLICT: não misturar escritores'; END IF;
 IF kind='primeline' THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador indisponível' USING ERRCODE='42501'; END IF;
  IF u.funcao='encarregado' AND NOT folha_privado.elegivel_equipa(person,d) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas equipa operacional elegível' USING ERRCODE='42501'; END IF;
  IF w IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.fn_quadro_resolver_data(d) WHERE colaborador_id=person AND obra_id=w)
 AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND u.funcao IN('diretor_obra','adjunto','preparador')) THEN RAISE EXCEPTION 'ALLOCATION_REQUIRED'; END IF;
 ELSE
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND ativo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo indisponível' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=w))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor não autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'EXTERNAL_DAY_REQUIRED'; END IF;
 END IF;
 IF row->>'conflict' IS NOT NULL THEN RAISE EXCEPTION '%',row->>'conflict'; END IF;
 SELECT * INTO old FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND CASE WHEN kind='primeline' THEN colaborador_id=person ELSE externo_id=person END FOR UPDATE;
 IF (p->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT folha_privado.adm_operacional() THEN
  window_days:=1;
  IF window_days IS NULL THEN RAISE EXCEPTION 'CORRECTION_WINDOW_UNCONFIGURED'; END IF;
  IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>window_days THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 END IF;
 IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>1 AND folha_privado.adm_operacional() AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
 f:=folha_privado.facts(p->'intervals',d); expected:=(row->>'expected_minutes')::integer;
 special:=extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND d=ANY(holiday_dates));
 IF EXISTS(SELECT 1 FROM public.folha_registos other,jsonb_array_elements(other.intervals) x,jsonb_array_elements(p->'intervals') y
 WHERE other.data=d AND other.obra_id IS DISTINCT FROM w AND (CASE WHEN kind='primeline' THEN other.colaborador_id=person ELSE other.externo_id=person END)
 AND (x->>'start')::time<coalesce((y->>'end')::time,'24:00'::time) AND (y->>'start')::time<coalesce((x->>'end')::time,'24:00'::time))
 THEN RAISE EXCEPTION 'INTERVAL_CONFLICT: outra obra'; END IF;
 state:=folha_privado.estado_efetivo((f->>'minutes')::integer,(f->>'open')::boolean,expected,row->'absence'<>'null'::jsonb,row->>'conflict' IS NOT NULL);
 IF kind='external' THEN state:=CASE WHEN row->>'conflict' IS NOT NULL OR coalesce(row->'absence'<>'null'::jsonb,false) THEN 'regularization' WHEN (f->>'open')::boolean THEN 'open' ELSE 'registered' END; expected:=NULL; END IF;
 IF NOT confirmar THEN RETURN jsonb_build_object('before',to_jsonb(old),'revision',coalesce(old.revision,0),'row',row,'facts',f,'state',state); END IF;
 IF old.id IS NOT NULL THEN
 UPDATE public.folha_registos SET intervals=p->'intervals',minutes=(f->>'minutes')::integer,estado=state,special_day=old.special_day,special_reviewed_at=NULL,special_reviewed_by=NULL,
 revision=old.revision+1,note=p->>'note',atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=old.id RETURNING * INTO result;
 ELSE
 INSERT INTO public.folha_registos(empresa_id,obra_id,tipo_local,data,colaborador_id,externo_id,intervals,minutes,estado,special_day,expected_minutes,revision,note,criado_por,atualizado_por,request_id)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,d,CASE WHEN kind='primeline' THEN person END,CASE WHEN kind='external' THEN person END,p->'intervals',(f->>'minutes')::integer,state,special,expected,coalesce(old.revision,0)+1,p->>'note',u.id,u.id,req)
 RETURNING * INTO result;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,kind,d,'save',to_jsonb(old),to_jsonb(result),result.revision,u.id,req,p->>'reason');
 IF kind='primeline' THEN PERFORM folha_privado.reconciliar_he(result); END IF;
 RETURN jsonb_build_object('result',to_jsonb(result));
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 req uuid:=(p_dados->>'request_id')::uuid; payload jsonb; op folha_privado.operacoes; preview jsonb:='[]'; keys jsonb:='[]';
 item jsonb; token text; result jsonb; person uuid; provider uuid; old_count integer;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF w IS NULL THEN
  IF p_acao<>'save' OR p_dados->'key'->>'kind' IS DISTINCT FROM 'primeline' THEN RAISE EXCEPTION 'PERMISSION_DENIED: escritório apenas Folha própria' USING ERRCODE='42501'; END IF;
  PERFORM folha_privado.local((p_dados->'key'->>'person_id')::uuid,w,true);
 ELSIF p_acao='save' THEN PERFORM folha_privado.local((p_dados->'key'->>'person_id')::uuid,w,true);
 ELSE PERFORM folha_privado.obra(w,true); END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR d IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 OR p_acao IS NULL OR p_acao NOT IN('save','bulk','allocate','transfer','remove_from_day','external_register') THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao IN('allocate','transfer','remove_from_day') THEN RAISE EXCEPTION 'TEAM_CONTRACT_REQUIRED: use fn_equipa_operar_v2'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  PERFORM folha_privado.autorizar_replay(p_acao,p_dados,w,d);
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token,'summary','Operação já registada; confirmar recupera o resultado.'); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF p_acao IN('save','bulk') THEN
  IF p_acao='save' THEN preview:=jsonb_build_array(folha_privado.save(p_dados,w,d,req,false));
  ELSE
   IF (p_dados->>'operation' IS DISTINCT FROM 'normal' AND (d<>(now() AT TIME ZONE 'Europe/Lisbon')::date OR p_dados->>'effective_time' IS NULL OR p_dados->>'effective_time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'))
   OR p_dados->>'operation' IS NULL OR p_dados->>'operation' NOT IN('start','finish','normal') OR jsonb_typeof(p_dados->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'items') NOT BETWEEN 1 AND 200
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'items') x GROUP BY x->'key'->>'person_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'VALIDATION_ERROR: bulk'; END IF;
   FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'items') ORDER BY value->'key'->>'person_id' LOOP
    IF item->'key'->>'kind'<>'primeline' OR EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=(item->'key'->>'person_id')::uuid AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT'; END IF;
    person:=(item->'key'->>'person_id')::uuid;
    IF p_dados->>'operation'='normal' THEN
     IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d)
      OR item->'intervals' IS DISTINCT FROM folha_privado.normal(person,w,d) THEN RAISE EXCEPTION 'NORMAL_DAY_CONFLICT'; END IF;
    ELSIF p_dados->>'operation'='start' THEN
     IF d<>(now() AT TIME ZONE 'Europe/Lisbon')::date OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=d)
      OR jsonb_array_length(item->'intervals')<>1 OR item->'intervals'->0->>'end' IS NOT NULL OR item->'intervals'->0->>'start' IS DISTINCT FROM p_dados->>'effective_time' THEN RAISE EXCEPTION 'BULK_START_CONFLICT'; END IF;
    ELSE
     IF NOT EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d AND estado='open')
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(item->'intervals') x WHERE x->>'end' IS NULL)
      OR EXISTS(SELECT 1 FROM public.folha_registos f,jsonb_array_elements(f.intervals) x WHERE f.colaborador_id=person AND f.obra_id=w AND f.data=d
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(item->'intervals') n WHERE n->>'start'=x->>'start' AND (CASE WHEN x->>'end' IS NULL THEN n->>'end'=p_dados->>'effective_time' ELSE n->>'end'=x->>'end' END)))
      OR (SELECT jsonb_array_length(intervals) FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d)<>jsonb_array_length(item->'intervals')
     THEN RAISE EXCEPTION 'BULK_FINISH_CONFLICT'; END IF;
    END IF;
    preview:=preview||jsonb_build_array(folha_privado.save(item,w,d,req,false));
   END LOOP;
  END IF;
 ELSIF p_acao IN('allocate','transfer','remove_from_day') THEN preview:=folha_privado.alocar(p_acao,p_dados,w,d,req,false);
 ELSE
  IF p_dados->>'role' IS NULL OR p_dados->>'role' NOT IN('pedreiro','servente') THEN RAISE EXCEPTION 'VALIDATION_ERROR: função externa'; END IF;
  result:=folha_privado.facts(p_dados->'intervals',d);
  provider:=(p_dados->>'provider_id')::uuid;
  PERFORM 1 FROM public.fornecedores f WHERE f.id=provider AND f.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND OR (NOT folha_privado.admin() AND NOT EXISTS(SELECT 1 FROM public.subempreitadas WHERE obra_id=w AND fornecedor_id=provider)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor' USING ERRCODE='42501'; END IF;
  IF length(btrim(coalesce(p_dados->>'name',''))) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'VALIDATION_ERROR: nome'; END IF;
  person:=coalesce((p_dados->>'external_id')::uuid,req);
  IF p_dados->>'external_id' IS NULL AND EXISTS(SELECT 1 FROM public.folha_externos WHERE empresa_id=u.empresa_id AND fornecedor_id=provider AND lower(btrim(nome))=lower(btrim(p_dados->>'name')))
  THEN RAISE EXCEPTION 'EXTERNAL_IDENTITY_EXISTS: reutilize a identidade existente; homónimos precisam de identificação operacional distinta'; END IF;
  IF p_dados->>'external_id' IS NOT NULL THEN
   PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND fornecedor_id=provider AND ativo AND nome=btrim(p_dados->>'name') FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: identidade externa' USING ERRCODE='42501'; END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d) THEN RAISE EXCEPTION 'EXTERNAL_DAY_EXISTS'; END IF;
  preview:=jsonb_build_object('provider',provider,'work',w,'person_id',person,'role',p_dados->>'role','facts',result);
 END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'snapshot',preview)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'summary',CASE WHEN p_acao='bulk' THEN format('Registar %s pessoas; %s excluídas. Exclusões: férias/ausências, conflitos, sem autorização ou ponto não elegível para esta ação. Confirmar?',jsonb_array_length(p_dados->'items'),jsonb_array_length(public.fn_folha_contexto_v2(d,w)->'rows')-jsonb_array_length(p_dados->'items')) WHEN p_acao='remove_from_day' THEN 'Retirar exclusivamente esta pessoa da equipa deste dia? O histórico será preservado.' WHEN p_acao='transfer' THEN 'Transferir da obra indicada para esta obra? O movimento e eventuais alertas serão preservados.' ELSE 'Confirmar estes factos na Folha de Ponto?' END,'preview',preview); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao IN('save','bulk') THEN
  FOR item IN SELECT value FROM jsonb_array_elements(CASE WHEN p_acao='save' THEN jsonb_build_array(p_dados) ELSE p_dados->'items' END) ORDER BY value->'key'->>'person_id' LOOP
   result:=folha_privado.save(item,w,d,req,true); keys:=keys||jsonb_build_array(item->'key');
  END LOOP;
 ELSIF p_acao IN('allocate','transfer','remove_from_day') THEN
  result:=folha_privado.alocar(p_acao,p_dados,w,d,req,true);
  keys:=jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p_dados->>'person_id','work_id',w,'date',d));
 ELSE
  IF p_dados->>'external_id' IS NULL THEN
   INSERT INTO public.folha_externos(id,empresa_id,fornecedor_id,nome,criado_por,origem_request)
   VALUES(person,u.empresa_id,provider,btrim(p_dados->>'name'),u.id,req);
  END IF;
  INSERT INTO public.folha_externos_dias(externo_id,empresa_id,obra_id,data,criado_por,criado_em,request_id,funcao) VALUES(person,u.empresa_id,w,d,u.id,now(),req,p_dados->>'role');
  result:=folha_privado.save(jsonb_build_object('key',jsonb_build_object('person_id',person,'kind','external','work_id',w,'date',d),'intervals',p_dados->'intervals','expected_revision',0,'reason',p_dados->>'reason','note',p_dados->>'note'),w,d,req,true);
  INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
   VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,'external',d,p_acao,NULL,jsonb_build_object('name',p_dados->>'name','provider_id',provider),0,u.id,req,NULL);
  keys:=jsonb_build_array(jsonb_build_object('kind','external','person_id',person,'work_id',w,'date',d));
 END IF;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys,'result',result);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname IN('elegivel_equipa','guardar_permanencia','proteger_alocacao_persistente') LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.sig); END LOOP; END $$;
CREATE OR REPLACE FUNCTION folha_privado.local(p uuid,w uuid,escrita boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; linked uuid; n integer;
BEGIN
 u:=folha_privado.ator();
 IF w IS NOT NULL THEN
 IF u.funcao IN('diretor_obra','adjunto','preparador') AND p IS NOT NULL
 AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id)
 AND (SELECT count(*) FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id)=1
 AND EXISTS(SELECT 1 FROM public.obras o JOIN public.obra_responsaveis r ON r.obra_id=o.id WHERE o.id=w AND o.empresa_id=u.empresa_id AND r.utilizador_id=u.id AND r.papel=u.funcao)
 THEN
  IF escrita THEN
   PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ligação própria alterada' USING ERRCODE='42501'; END IF;
   PERFORM 1 FROM public.obras o JOIN public.obra_responsaveis r ON r.obra_id=o.id WHERE o.id=w AND o.empresa_id=u.empresa_id AND r.utilizador_id=u.id AND r.papel=u.funcao FOR SHARE OF o,r;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: responsabilidade alterada' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN;
 END IF;
 PERFORM folha_privado.obra(w,escrita); RETURN;
 END IF;
 IF escrita THEN SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF; END IF;
 IF folha_privado.admin() THEN
  IF p IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  RETURN;
 END IF;
 IF escrita THEN
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ligação própria alterada' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT count(*),min(c.id::text)::uuid INTO n,linked FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id;
 IF u.funcao NOT IN('diretor_obra','adjunto','preparador') OR n<>1 OR (p IS NOT NULL AND p<>linked)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas a própria Folha de escritório' USING ERRCODE='42501'; END IF;
END $$;
-- Both clients call the same persistent team writer. Non-operational rows retain the reviewed daily contract.
DO $$ DECLARE original text; BEGIN
 original:=pg_get_functiondef('public.fn_quadro_operar_v1(text,jsonb,boolean,text)'::regprocedure);
 original:=replace(original,'public.fn_quadro_operar_v1(','folha_privado.quadro_diario_preservado(');
 EXECUTE original;
 original:=pg_get_functiondef('public.fn_quadro_contexto_v1(date,date)'::regprocedure);
 original:=replace(original,'public.fn_quadro_contexto_v1(','folha_privado.quadro_contexto_preservado(');
 EXECUTE original;
END $$;
REVOKE ALL ON FUNCTION folha_privado.quadro_diario_preservado(text,jsonb,boolean,text),folha_privado.quadro_contexto_preservado(date,date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.fn_quadro_operar_v1(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; p uuid; d date; w uuid; e public.quadro_equipa_permanencias; body jsonb; r jsonb; rev integer; daily_rev integer; action text; op folha_privado.operacoes;
BEGIN
 u:=folha_privado.ator();
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo FOR SHARE;
 IF p_acao='renomear_linha' THEN RETURN folha_privado.quadro_diario_preservado(p_acao,p_dados,p_confirmar,p_versao); END IF;
 p:=(p_dados->>'colaborador_id')::uuid;d:=(p_dados->>'data')::date;w:=(p_dados->>'obra_id')::uuid;
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=(p_dados->>'request_id')::uuid;
 IF FOUND AND op.payload->'data' ? 'quadro_request' THEN
  IF op.payload->'data'->'quadro_request' IS DISTINCT FROM p_dados OR op.payload->'data'->>'quadro_action' IS DISTINCT FROM p_acao THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  r:=public.fn_equipa_operar_v2(op.payload->>'action',op.payload->'data',p_confirmar,p_versao);
  IF NOT p_confirmar THEN RETURN r||jsonb_build_object('version',1,'team_contract',1); END IF;
  RETURN op.resultado->'quadro_result';
 END IF;
 IF NOT folha_privado.elegivel_equipa(p,d) THEN
  IF u.funcao='encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas Pedreiro/Servente interno ativo' USING ERRCODE='42501'; END IF;
  RETURN folha_privado.quadro_diario_preservado(p_acao,p_dados,p_confirmar,p_versao);
 END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF p_dados->>'version' IS DISTINCT FROM '1' OR p_acao IS NULL OR p_acao NOT IN('alocar','adicionar','mover','remover')
 THEN RAISE EXCEPTION 'TEAM_CONTRACT_REQUIRED'; END IF;
 SELECT * INTO e FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d);
 SELECT coalesce((SELECT revision FROM folha_privado.equipa_revisoes WHERE colaborador_id=p),0) INTO rev;
 SELECT coalesce((SELECT revisao FROM public.quadro_dias_revisoes WHERE colaborador_id=p AND data=d),0) INTO daily_rev;
 IF (p_dados->>'expected_revision')::integer IS DISTINCT FROM (CASE WHEN e.id IS NULL THEN daily_rev ELSE rev END)
 THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF p_acao='remover' THEN
  IF e.id IS NULL OR p_dados->'ids' IS DISTINCT FROM (SELECT coalesce(jsonb_agg(q.id ORDER BY q.id),'[]'::jsonb) FROM public.fn_quadro_resolver_data(d) q WHERE q.colaborador_id=p) THEN RAISE EXCEPTION 'TEAM_HISTORY_READ_ONLY: retirar permanência pela Folha'; END IF;
  w:=e.obra_id;action:='team_remove';
 ELSE
  IF p_dados->>'periodo' IS DISTINCT FROM 'dia_inteiro' OR p_dados->>'tipo_alocacao' IS DISTINCT FROM 'obra'
  THEN RAISE EXCEPTION 'TEAM_FULL_DAY_REQUIRED: equipa física permanece na obra; registe intervalos na Folha'; END IF;
  action:=CASE WHEN e.id IS NULL THEN 'team_add' ELSE 'team_transfer' END;
 END IF;
 body:=jsonb_build_object('version',2,'request_id',p_dados->>'request_id','work_id',w,'date',d,
 'people',jsonb_build_array(jsonb_build_object('person_id',p,'expected_revision',rev,'source_work_id',e.obra_id)),'quadro_request',p_dados,'quadro_action',p_acao);
 r:=public.fn_equipa_operar_v2(action,body,p_confirmar,p_versao);
 r:=r||jsonb_build_object('version',1,'team_contract',1,'revision',rev+CASE WHEN p_confirmar THEN 1 ELSE 0 END,'allocations',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]'::jsonb) FROM public.fn_quadro_resolver_data(d) q WHERE q.colaborador_id=p));
 IF p_confirmar THEN UPDATE folha_privado.operacoes SET resultado=resultado||jsonb_build_object('quadro_result',r) WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=(p_dados->>'request_id')::uuid; END IF;
 RETURN r;
END $$;
CREATE OR REPLACE FUNCTION public.fn_quadro_contexto_v1(p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb; extra jsonb;
BEGIN
 c:=folha_privado.quadro_contexto_preservado(p_inicio,p_fim);
 SELECT coalesce(jsonb_agg(jsonb_build_object('colaborador_id',e.colaborador_id,'data',d.data::date,'revisao',r.revision,'obras_visiveis',jsonb_build_array(e.obra_id))),'[]') INTO extra
 FROM public.quadro_equipa_permanencias e JOIN folha_privado.equipa_revisoes r ON r.colaborador_id=e.colaborador_id
 CROSS JOIN generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') d(data)
 WHERE e.empresa_id=(folha_privado.ator()).empresa_id AND e.inicio<=d.data::date AND (e.fim IS NULL OR e.fim>d.data::date)
 AND public.fn_quadro_ler_obra(e.obra_id);
 RETURN c||jsonb_build_object('revisions',coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements(c->'revisions') x
 WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(extra) y WHERE y->>'colaborador_id'=x->>'colaborador_id' AND y->>'data'=x->>'data')),'[]')||extra,'team_contract',1);
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
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
  UPDATE public.folha_he SET estado=after->>'estado',revision=rev+1,prazo_processamento=CASE WHEN p_acao='he_validate' THEN folha_privado.prazo_he(u.empresa_id,f.data) ELSE prazo_processamento END WHERE id=entity RETURNING * INTO h;
  IF p_acao='he_validate' AND h.prazo_processamento IS NOT NULL THEN
   INSERT INTO public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave)
   SELECT u.empresa_id,NULL,'folha_he_processamento','folha_he',h.id,'HE validada: processamento pendente',h.prazo_processamento,dest.id,false,req FROM public.utilizadores dest WHERE dest.empresa_id=u.empresa_id AND dest.ativo AND dest.funcao='administrativo';
  END IF;
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
CREATE OR REPLACE FUNCTION folha_privado.normal(p uuid,w uuid,d date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r jsonb; xs jsonb; full_day jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=(folha_privado.ator()).empresa_id AND calendar_complete AND extract(year FROM d)::integer=ANY(calendar_validated_years)) THEN RAISE EXCEPTION 'CALENDAR_REQUIRED: dia normal automático'; END IF;
 IF extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=(folha_privado.ator()).empresa_id AND d=ANY(holiday_dates)) THEN RAISE EXCEPTION 'SPECIAL_DAY_NO_NORMAL_FILL'; END IF;
 r:=folha_privado.linha(p,w,d,'primeline');
 SELECT intervals INTO full_day FROM public.folha_horarios WHERE obra_id=w;
 IF full_day IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(full_day,d);
 SELECT jsonb_agg(jsonb_build_object('start',x->>'start','end',x->>'end') ORDER BY x->>'start') INTO xs
 FROM public.folha_horarios h,jsonb_array_elements(h.intervals) x WHERE h.obra_id=w AND (r->>'period'='dia_inteiro' OR x->>'period'=r->>'period');
 IF xs IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(xs,d); RETURN xs;
END $$;
-- Enrich only reports already authorized by the installed management reader.
DO $$ BEGIN EXECUTE replace(pg_get_functiondef('public.fn_folha_gestao_contexto_v2(uuid,uuid,date)'::regprocedure),'public.fn_folha_gestao_contexto_v2(','folha_privado.gestao_contexto_preservado('); END $$;
REVOKE ALL ON FUNCTION folha_privado.gestao_contexto_preservado(uuid,uuid,date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.fn_folha_gestao_contexto_v2(p_obra_id uuid DEFAULT NULL,p_colaborador_id uuid DEFAULT NULL,p_competencia date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE response jsonb; u public.utilizadores;
BEGIN
 response:=folha_privado.gestao_contexto_preservado(p_obra_id,p_colaborador_id,p_competencia);u:=folha_privado.ator();
 RETURN response||jsonb_build_object('task_reports',coalesce((SELECT jsonb_agg(x.value||jsonb_build_object('reportado_nome',a.nome) ORDER BY x.value->>'id') FROM jsonb_array_elements(response->'task_reports') x LEFT JOIN public.utilizadores a ON a.id=(x.value->>'reportado_por')::uuid AND a.empresa_id=u.empresa_id),'[]'::jsonb));
END $$;
COMMIT;
