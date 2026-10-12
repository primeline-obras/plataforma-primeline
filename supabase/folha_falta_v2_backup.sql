-- Exige autorização separada; nenhuma execução real nesta tarefa.
BEGIN;
LOCK TABLE public.ausencias IN SHARE MODE;
CREATE SCHEMA IF NOT EXISTS primeline_backup;
REVOKE ALL ON SCHEMA primeline_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_backup.falta_ausencias_20261012 AS TABLE public.ausencias;
CREATE TABLE primeline_backup.falta_constraints_20261012 AS SELECT conname,pg_get_constraintdef(oid) definicao FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND contype='c';
CREATE TABLE primeline_backup.falta_policies_20261012 AS SELECT * FROM pg_policies WHERE schemaname='public' AND tablename='ausencias';
CREATE TABLE primeline_backup.falta_acl_20261012 AS SELECT relacl FROM pg_class WHERE oid='public.ausencias'::regclass;
REVOKE ALL ON TABLE primeline_backup.falta_ausencias_20261012,primeline_backup.falta_constraints_20261012,primeline_backup.falta_policies_20261012,primeline_backup.falta_acl_20261012 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
