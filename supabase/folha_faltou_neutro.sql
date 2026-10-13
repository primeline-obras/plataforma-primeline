-- LOCAL ONLY. Exact HR-27 baseline; private backup; no legacy writer reopened.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;SELECT pg_advisory_xact_lock(61001,1);LOCK TABLE public.ausencias,public.ausencias_anexos,public.folha_registos,public.ponto_pessoal_obra,public.lancamentos_mao_obra,public.horas_extraordinarias,public.quadro_pessoal_movimentos,public.quadro_equipa_permanencias,public.folha_historico,public.folha_gestao_historico,public.folha_avaliacoes_diarias,public.folha_vencimentos,public.alertas,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $hours_dependencies$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.ator()') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='176c4fb030401fb45c89f3cd1616a9d26e9e15b691ff524a33dfc8d233c6b079' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.ator()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.obra(uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='731f5289cd29bdb7f7d69723fabb76cbb8b8e577bb474c679f991c7271d9788e' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.obra(uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.lock_dia(uuid,date)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='b29022304f316e25dd34bae7a1e1906a0dfd72bd041a1d658338cc8394745502' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.lock_dia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.local(uuid,uuid,boolean)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='9eb2f0d8b7e52d5280f0798c48cb8ec84377281c1e13706bc066b1cf3765070b' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner )) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: folha_privado.local(uuid,uuid,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_contexto_v2(date,uuid)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5ca6e224708a655a9c778fa6a5701b39e6c0aab8dbf0a01a87ffb77d42ea095' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner AND x.grantee<>'authenticated'::regrole)) THEN RAISE EXCEPTION 'HORAS_AUTHORIZATION_DEPENDENCY_DRIFT: public.fn_folha_contexto_v2(date,uuid)';END IF;
END $hours_dependencies$;DO $baseline$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_gestao_v2(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='97b41cd118aa9efee1fb960bf2d9d39585b3e4e7f525c624372e13adf374c856' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: public.fn_folha_gestao_v2(text,jsonb,boolean,text)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='1da2681dfd6b92af5b425901ef76bee058d37e36d45e3f4ffb1985423d2881f5' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)';END IF;
IF has_function_privilege('authenticated','public.fn_guardar_ponto_obra(uuid,uuid,date,text,time,time,time,time,text)','EXECUTE') THEN RAISE EXCEPTION 'FALTOU_LEGACY_WRITER_NOT_CLOSED';END IF;
IF (SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='ausencias' AND column_name='tipo') NOT IN('text','character varying') THEN RAISE EXCEPTION 'FALTOU_REQUIRES_TEXT_TYPE';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='trg_folha_vencimentos_ausencia' AND tgenabled='O') THEN RAISE EXCEPTION 'FALTOU_RECONCILIATION_REQUIRED';END IF;
IF EXISTS(SELECT 1 FROM public.ausencias WHERE tipo='falta_reportada_pendente') THEN RAISE EXCEPTION 'FALTOU_UNTRACKED_EXISTING_REPORT';END IF;
END $baseline$;
DO $absent$ BEGIN IF to_regprocedure('public.fn_folha_faltou_v2(text,jsonb,boolean,text)') IS NOT NULL OR to_regprocedure('public.fn_folha_falta_v2(text,jsonb,boolean,text)') IS NOT NULL OR to_regprocedure('folha_privado.faltou_controlado_guardar()') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='folha_faltou_controlado') THEN RAISE EXCEPTION 'FALTOU_PRESENT_OR_OLD_WRITER';END IF;END $absent$;
DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_faltou_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_faltou_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE n.nspname='primeline_faltou_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_faltou_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'FALTOU_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_faltou_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'FALTOU_DATA_DRIFT: %',r.tabela;END IF;END LOOP;
END $data$;
DO $structure$ DECLARE j jsonb;BEGIN SELECT jsonb_build_object('rls',relrowsecurity,'owner',relowner::regrole::text,'acl',relacl::text,'column_acl',(SELECT coalesce(jsonb_agg(jsonb_build_array(attname,attacl::text) ORDER BY attnum),'[]') FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped),'policies',(SELECT coalesce(jsonb_agg(pg_get_expr(polqual,polrelid)||coalesce(pg_get_expr(polwithcheck,polrelid),'') ORDER BY polname),'[]') FROM pg_policy WHERE polrelid=c.oid)) INTO j FROM pg_class c WHERE c.oid='public.ausencias'::regclass;IF j IS DISTINCT FROM (SELECT metadata FROM primeline_faltou_backup.estrutura) THEN RAISE EXCEPTION 'FALTOU_EXISTING_SECURITY_DRIFT';END IF;END $structure$;
DO $constraints$ DECLARE r record;BEGIN FOR r IN SELECT * FROM primeline_faltou_backup.constraints WHERE definition LIKE '%tipo%' LOOP EXECUTE format('ALTER TABLE public.ausencias DROP CONSTRAINT %I',r.conname);EXECUTE format('ALTER TABLE public.ausencias ADD CONSTRAINT %I CHECK ((%s) OR (tipo=''falta_reportada_pendente'' AND estado=''ausente_pendente''))',r.conname,r.expr);END LOOP;END $constraints$;
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
DO $installed$ DECLARE r record;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_gestao_v2(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='97b41cd118aa9efee1fb960bf2d9d39585b3e4e7f525c624372e13adf374c856' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: public.fn_folha_gestao_v2(text,jsonb,boolean,text)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='1da2681dfd6b92af5b425901ef76bee058d37e36d45e3f4ffb1985423d2881f5' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.faltou_controlado_guardar()') AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='a66f0879fd4d1a348bddbee45e409e84be02fd0906ea2ad36b3b005015025332' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: folha_privado.faltou_controlado_guardar()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.fn_folha_faltou_v2(text,jsonb,boolean,text)') AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='094dc4ab55da2be8d497dc8d7b99f6fc15b24e76ca81e014c6f244d17425fe6e' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'FALTOU_FUNCTION_DRIFT: public.fn_folha_faltou_v2(text,jsonb,boolean,text)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='folha_faltou_controlado' AND tgenabled='O' AND tgfoid='folha_privado.faltou_controlado_guardar()'::regprocedure AND tgtype=31 AND tgnargs=0 AND tgqual IS NULL) THEN RAISE EXCEPTION 'FALTOU_TRIGGER_DRIFT';END IF;
FOR r IN SELECT * FROM primeline_faltou_backup.constraints WHERE definition LIKE '%tipo%' LOOP IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND conname=r.conname AND convalidated AND pg_get_constraintdef(oid) LIKE '%falta_reportada_pendente%') THEN RAISE EXCEPTION 'FALTOU_CONSTRAINT_DRIFT';END IF;END LOOP;END $installed$;
DO $structure$ DECLARE j jsonb;BEGIN SELECT jsonb_build_object('rls',relrowsecurity,'owner',relowner::regrole::text,'acl',relacl::text,'column_acl',(SELECT coalesce(jsonb_agg(jsonb_build_array(attname,attacl::text) ORDER BY attnum),'[]') FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped),'policies',(SELECT coalesce(jsonb_agg(pg_get_expr(polqual,polrelid)||coalesce(pg_get_expr(polwithcheck,polrelid),'') ORDER BY polname),'[]') FROM pg_policy WHERE polrelid=c.oid)) INTO j FROM pg_class c WHERE c.oid='public.ausencias'::regclass;IF j IS DISTINCT FROM (SELECT metadata FROM primeline_faltou_backup.estrutura) THEN RAISE EXCEPTION 'FALTOU_EXISTING_SECURITY_DRIFT';END IF;END $structure$;
DO $data$ DECLARE r record;j jsonb;BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_faltou_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_faltou_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE n.nspname='primeline_faltou_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_faltou_backup' AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'FALTOU_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_faltou_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'FALTOU_DATA_DRIFT: %',r.tabela;END IF;END LOOP;
END $data$;
SELECT 'FALTOU_INSTALLED' resultado;COMMIT;
