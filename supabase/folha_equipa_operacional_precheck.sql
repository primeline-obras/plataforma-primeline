BEGIN READ ONLY;
DO $$ DECLARE sig text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regclass('public.quadro_equipa_permanencias') IS NOT NULL OR to_regclass('folha_privado.equipa_revisoes') IS NOT NULL
 THEN RAISE EXCEPTION 'ALREADY_INSTALLED'; END IF;
 IF to_regprocedure('public.fn_equipa_operar_v2(text,jsonb,boolean,text)') IS NOT NULL OR to_regprocedure('public.fn_folha_ferias_mapa_v2(date,date)') IS NOT NULL
 OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='folha_externos_dias' AND column_name='funcao') THEN RAISE EXCEPTION 'PARTIAL_OR_DIFFERENT_INSTALLATION'; END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN('colaboradores','obras','utilizadores') AND column_name='delegacao')
 THEN RAISE EXCEPTION 'DELEGATION_MODEL_CHANGED: reutilizar após revisão'; END IF;
 FOREACH sig IN ARRAY ARRAY['public.fn_folha_operar_v2(text,jsonb,boolean,text)','public.fn_folha_contexto_v2(date,uuid)',
 'public.fn_folha_pessoas_v2(date,uuid)','public.fn_quadro_resolver_data(date)','folha_privado.linha(uuid,uuid,date,text)',
 'folha_privado.save(jsonb,uuid,date,uuid,boolean)','public.fn_folha_gestao_v2(text,jsonb,boolean,text)','public.fn_folha_gestao_contexto_v2(uuid,uuid,date)'] LOOP
  IF to_regprocedure(sig) IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FUNCTION: %',sig; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(sig) AND prosecdef) THEN RAISE EXCEPTION 'UNEXPECTED_FUNCTION_SECURITY: %',sig; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.ponto_pessoal_obra'::regclass AND t.tgname='trg_01_folha_legacy_closed' AND t.tgfoid=to_regprocedure('folha_privado.legacy_closed()') AND t.tgtype=62 AND t.tgenabled IN('O','A')) THEN RAISE EXCEPTION 'LEGACY_CUTOVER_UNCONFIRMED'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.local(uuid,uuid,boolean)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '981dc2ae8f873aef0138520a13c5ff476925663ef75109d5d157c2038fad310b' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.local'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.linha(uuid,uuid,date,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '10ef71c91baf7490b5707597a0f8ce95b90633d1a7188f3e9513fa5594b97cbc' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.linha'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.save(jsonb,uuid,date,uuid,boolean)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM 'df3886df93ab0b696980f05699cb1f04e412622e2233da84ededf219f1e8fac2' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.save'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.normal(uuid,uuid,date)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM 'b074005aa19185b162c09ba957e4b2e4faca4723e6a81247b2d10e7953b5b03a' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: folha_privado.normal'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_contexto_v2(date,uuid)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '3a7eb0e02b9f07ebd7ccc8d7b6d826cb507d447171b10b2fbbd46edcde5954cf' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_contexto_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_pessoas_v2(date,uuid)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '845c9e8761b2f0625241a9f0571ca9cf0f48f1f1bdf7de7acfa0d042cbb411f6' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_pessoas_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_operar_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '9571c6e063d0f65edbd2a83d3035bcb0b581c711f33f65ac200da38ebc5d87de' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_operar_v2'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM '5c9aba5e347726b6a0d284c3d661aa5fbdc9b9f24d251eaa95b978d3251a06c6' THEN RAISE EXCEPTION 'FUNCTION_DRIFT: public.fn_folha_gestao_v2'; END IF;
 RAISE NOTICE 'FOLHA_EQUIPA_PRECHECK_OK';
END $$;
SELECT c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN('folha_registos','folha_historico','quadro_pessoal_alocacao','quadro_pessoal_movimentos');
COMMIT;
