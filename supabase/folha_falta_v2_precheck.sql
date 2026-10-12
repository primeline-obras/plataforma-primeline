-- Somente leitura; executar novamente antes de qualquer rollout autorizado.
BEGIN READ ONLY;
SELECT to_regprocedure('public.fn_folha_falta_v2(text,jsonb,boolean,text)') AS rpc_deve_estar_ausente;
SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.ausencias'::regclass;
SELECT p.oid::regprocedure,pg_get_functiondef(p.oid),p.proacl FROM pg_proc p WHERE p.oid IN(to_regprocedure('folha_privado.ator()'),to_regprocedure('folha_privado.adm()'),to_regprocedure('folha_privado.obra(uuid,boolean)'),to_regprocedure('folha_privado.lock_dia(uuid,date)'),to_regprocedure('folha_privado.linha(uuid,uuid,date,text)'));
SELECT * FROM pg_policies WHERE schemaname='public' AND tablename='ausencias';
SELECT tgname,tgenabled,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND NOT tgisinternal;
SELECT to_regclass('primeline_backup.falta_ausencias_20261012') AS backup_deve_estar_ausente;
SELECT table_name,column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name IN('folha_registos','ponto_pessoal_obra','lancamentos_mao_obra','horas_extraordinarias','quadro_equipa_permanencias') ORDER BY table_name,ordinal_position;
ROLLBACK;
