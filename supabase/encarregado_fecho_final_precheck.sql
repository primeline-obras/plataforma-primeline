BEGIN TRANSACTION READ ONLY;
DO $$ DECLARE r record; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regnamespace('primeline_encarregado_final_backup') IS NOT NULL OR to_regclass('public.folha_externos_permanencias') IS NOT NULL THEN RAISE EXCEPTION 'ALREADY_INSTALLED_OR_BACKUP_PRESENT'; END IF;
 FOR r IN SELECT * FROM (VALUES ('public.fn_listar_colegas_agenda()','93127401177f7763624f88b581eadf68'),
('folha_privado.facts(jsonb,date)','3eb9bc9ffe17363f30f925901a631c80'),
('folha_privado.local(uuid,uuid,boolean)','d2c83f8f24e1571a411da6663f907f97'),
('folha_privado.linha(uuid,uuid,date,text)','8154e88e10b38921f0af4e0ba4e4da8e'),
('folha_privado.save(jsonb,uuid,date,uuid,boolean)','811c7c791efe79a664f812855c7820e6'),
('folha_privado.normal(uuid,uuid,date)','4494cc93c7317ea0164da968d3cf7002'),
('public.fn_equipa_operar_v2(text,jsonb,boolean,text)','cb3ba9772a6959a628827c4076f800da'),
('public.fn_folha_pessoas_v2(date,uuid)','9cc4f3dffcf2c4899599015c8046ccf6'),
('public.fn_folha_contexto_v2(date,uuid)','3dcfd7360ec89cebf9f2d4b1fe5a9bc1'),
('public.fn_folha_operar_v2(text,jsonb,boolean,text)','7172ac4a5a13cb90a00cd890f39c16bd')) x(sig,hash) LOOP
 IF to_regprocedure(r.sig) IS NULL OR (SELECT proowner FROM pg_proc WHERE oid=to_regprocedure(r.sig)) IS DISTINCT FROM 'postgres'::regrole OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(r.sig))<>r.hash THEN RAISE EXCEPTION 'BASELINE_DIVERGENCE: %',r.sig; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O') THEN RAISE EXCEPTION 'LEGACY_CUTOVER_REQUIRED'; END IF;
 IF to_regprocedure('public.fn_listar_colegas_agenda()') IS NULL THEN RAISE EXCEPTION 'AGENDA_READER_REQUIRED'; END IF;
END $$;
SELECT 'ENCARREGADO_FINAL_PRECHECK_OK' AS resultado;
COMMIT;
