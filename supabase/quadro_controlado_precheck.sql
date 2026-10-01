-- PRECHECK somente leitura: rever também cada definição dinâmica devolvida.
SELECT count(*) AS alocacoes FROM public.quadro_pessoal_alocacao;
SELECT count(*) AS movimentos FROM public.quadro_pessoal_movimentos;
SELECT a.id,b.id,a.colaborador_id,a.data,a.periodo,b.periodo
FROM public.quadro_pessoal_alocacao a JOIN public.quadro_pessoal_alocacao b
 ON a.id<b.id AND a.colaborador_id=b.colaborador_id AND a.data=b.data
WHERE a.periodo='dia_inteiro' OR b.periodo='dia_inteiro' OR a.periodo=b.periodo;
SELECT q.id AS alocacao_id,a.id AS ausencia_id,a.estado,a.tipo FROM public.quadro_pessoal_alocacao q
 JOIN public.ausencias a ON a.colaborador_id=q.colaborador_id AND a.data=q.data;
SELECT p.oid::regprocedure::text assinatura,p.prosecdef,p.proacl,pg_get_functiondef(p.oid) definicao
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind IN('f','p') AND (p.prosrc ILIKE '%quadro%' OR p.prosrc ~* '\mexecute\M' OR p.proname LIKE 'fn_rh_%');
SELECT tgname,tgenabled,pg_get_triggerdef(oid) FROM pg_trigger
WHERE tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT tgisinternal;
SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos');
SELECT conrelid::regclass,pg_get_constraintdef(oid) FROM pg_constraint WHERE confrelid='public.quadro_pessoal_alocacao'::regclass;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.quadro_pessoal_alocacao)<>227 OR (SELECT count(*) FROM public.quadro_pessoal_movimentos)<>98 THEN RAISE EXCEPTION 'PRECONDITION_FAILED: fotografia 227/98 divergente; PARAR e rever.'; END IF;
 IF to_regclass('public.quadro_operacoes') IS NOT NULL OR to_regclass('public.quadro_dias_revisoes') IS NOT NULL
 OR to_regprocedure('public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)') IS NOT NULL
 THEN RAISE EXCEPTION 'PRECONDITION_FAILED: objetos do pacote já presentes.'; END IF;
END $$;
