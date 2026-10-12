-- Rollback estrutural condicionado; preservar backups e histórico.
BEGIN;
LOCK TABLE public.ausencias IN ACCESS EXCLUSIVE MODE;
DO $$ DECLARE c record; BEGIN
 IF EXISTS(SELECT 1 FROM public.ausencias WHERE tipo='falta_justificada_pendente') THEN RAISE EXCEPTION 'ROLLBACK_BLOCKED: classificar ocorrências pendentes primeiro; não apagar dados'; END IF;
 IF to_regclass('primeline_backup.falta_constraints_20261012') IS NULL THEN RAISE EXCEPTION 'ROLLBACK_BLOCKED: backup obrigatório'; END IF;
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND contype='c' LOOP EXECUTE format('ALTER TABLE public.ausencias DROP CONSTRAINT %I',c.conname); END LOOP;
 FOR c IN SELECT conname,definicao FROM primeline_backup.falta_constraints_20261012 LOOP EXECUTE format('ALTER TABLE public.ausencias ADD CONSTRAINT %I %s',c.conname,c.definicao); END LOOP;
END $$;
DROP TRIGGER trg_falta_classificacao ON public.ausencias;
DROP FUNCTION folha_privado.proteger_classificacao_falta();
DROP FUNCTION public.fn_folha_falta_v2(text,jsonb,boolean,text);
COMMIT;
