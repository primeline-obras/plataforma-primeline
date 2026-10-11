import json, pathlib, hashlib, re
root=pathlib.Path(__file__).resolve().parents[1]
base=json.loads((root/'tests/fixtures/pacote2-real-baseline-20261007.json').read_text(encoding='utf-8-sig'))
names=['debitos_diretos','debitos_diretos_lancamentos']
sigs=['fn_economico_ator_atual()','fn_financeiro_autorizar_obra(uuid,boolean)','fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)','fn_log_importacao_xlsx(text,text,integer,jsonb)','fn_e_administrativo()','fn_e_financeiro()','fn_utilizador_atual_id()']
contract={ 'source':'Committed catalog capture 2026-10-07; must be reconfirmed read-only before real rollout', 'tables':[t for t in base['tables'] if t['schema']=='public' and t['name'] in names], 'functions':[f for f in base['functions'] if f['signature'] in sigs] }
(root/'tests/fixtures/financeiro-debitos-baseline-20261011.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
expected=json.dumps([{'signature':f['signature'],'hash':f['definition_sha256']} for f in contract['functions']],ensure_ascii=False)
table_contract=json.dumps(contract['tables'],ensure_ascii=False)
function_contract=json.dumps(contract['functions'],ensure_ascii=False)
catalog_check=r"""
DO $catalog$ DECLARE t jsonb; c jsonb; p jsonb; tr jsonb; rel regclass; actual jsonb; BEGIN
 FOR t IN SELECT value FROM jsonb_array_elements($tables$TABLE_CONTRACT$tables$::jsonb) LOOP
  rel:=('public.'||(t->>'name'))::regclass;
  IF (SELECT array_agg(x ORDER BY x) FROM unnest(string_to_array(trim(both '{}' from (SELECT relacl::text FROM pg_class WHERE oid=rel)),',')) x) IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(string_to_array(trim(both '{}' from t->>'acl'),',')) x) THEN RAISE EXCEPTION 'TABLE_ACL_DRIFT: %',rel; END IF;
  IF (SELECT relforcerowsecurity FROM pg_class WHERE oid=rel) IS DISTINCT FROM (t->>'force_rls')::boolean THEN RAISE EXCEPTION 'FORCE_RLS_DRIFT: %',rel; END IF;
  FOR c IN SELECT value FROM jsonb_array_elements(t->'columns') LOOP
   SELECT jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'nullable',NOT a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl::text) INTO actual FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=rel AND a.attname=c->>'name' AND NOT a.attisdropped;
   IF actual IS DISTINCT FROM c-'name' THEN RAISE EXCEPTION 'COLUMN_CONTRACT_DRIFT: %.%',rel,c->>'name'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_policy WHERE polrelid=rel)<>jsonb_array_length(t->'policies') THEN RAISE EXCEPTION 'POLICY_COUNT_DRIFT: %',rel; END IF;
  FOR p IN SELECT value FROM jsonb_array_elements(t->'policies') LOOP
   SELECT to_jsonb(v) INTO actual FROM pg_policies v WHERE schemaname='public' AND tablename=t->>'name' AND policyname=p->>'policyname';
   IF actual IS DISTINCT FROM p THEN RAISE EXCEPTION 'POLICY_CONTRACT_DRIFT: %.%',rel,p->>'policyname'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_constraint WHERE conrelid=rel)<>jsonb_array_length(t->'constraints') THEN RAISE EXCEPTION 'CONSTRAINT_COUNT_DRIFT: %',rel; END IF;
  FOR c IN SELECT value FROM jsonb_array_elements(t->'constraints') LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=rel AND conname=c->>'name' AND contype::text=c->>'type' AND convalidated=(c->>'validated')::boolean AND pg_get_constraintdef(oid)=c->>'definition') THEN RAISE EXCEPTION 'CONSTRAINT_CONTRACT_DRIFT: %.%',rel,c->>'name'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid=rel AND NOT tgisinternal)<>jsonb_array_length(t->'triggers') THEN RAISE EXCEPTION 'TRIGGER_COUNT_DRIFT: %',rel; END IF;
  FOR tr IN SELECT value FROM jsonb_array_elements(t->'triggers') LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=rel AND tgname=tr->>'name' AND tgenabled::text=tr->>'enabled' AND pg_get_triggerdef(oid)=tr->>'definition') THEN RAISE EXCEPTION 'AUDIT_TRIGGER_DRIFT: %',rel; END IF;
  END LOOP;
 END LOOP;
END $catalog$;
""".replace('TABLE_CONTRACT',table_contract)
check=r"""
DO $check$ DECLARE f jsonb; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regnamespace('financeiro_debitos_privado') IS NOT NULL THEN RAISE EXCEPTION 'INSTALLATION_PRESENT_OR_PARTIAL'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid IN('public.debitos_diretos'::regclass,'public.debitos_diretos_lancamentos'::regclass) AND attname='empresa_id' AND NOT attisdropped) THEN RAISE EXCEPTION 'INSTALLATION_PRESENT_OR_PARTIAL'; END IF;
 IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid='public.debitos_diretos'::regclass AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM ARRAY['id','obra_id','descricao','categoria','valor_previsto','recorrencia','dia_mes','data_inicio','data_fim','ativo','criado_por','criado_em'] THEN RAISE EXCEPTION 'DEBIT_SCHEMA_DRIFT'; END IF;
 IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute WHERE attrelid='public.debitos_diretos_lancamentos'::regclass AND attnum>0 AND NOT attisdropped) IS DISTINCT FROM ARRAY['id','debito_direto_id','data','valor','criado_em'] THEN RAISE EXCEPTION 'ENTRY_SCHEMA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.debitos_diretos'::regclass,'public.debitos_diretos_lancamentos'::regclass) AND (NOT relrowsecurity OR relowner<>'postgres'::regrole)) THEN RAISE EXCEPTION 'OWNER_RLS_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.debitos_diretos'::regclass AND conname='debitos_diretos_obra_id_fkey' AND contype='f' AND confrelid='public.obras'::regclass AND convalidated) OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.debitos_diretos_lancamentos'::regclass AND conname='debitos_diretos_lancamentos_debito_direto_id_fkey' AND contype='f' AND confrelid='public.debitos_diretos'::regclass AND convalidated) THEN RAISE EXCEPTION 'FK_CONTRACT_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.debitos_diretos'::regclass AND contype='p' AND pg_get_constraintdef(oid)='PRIMARY KEY (id)') OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.debitos_diretos_lancamentos'::regclass AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (debito_direto_id, data)') THEN RAISE EXCEPTION 'KEY_CONTRACT_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid IN('public.debitos_diretos'::regclass,'public.debitos_diretos_lancamentos'::regclass) AND polcmd IN('w','d','*')) THEN RAISE EXCEPTION 'UNREVIEWED_EDIT_DELETE_POLICY'; END IF;
 IF EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.administradores_plataforma a ON a.utilizador_id=u.id WHERE u.ativo IS TRUE AND u.funcao='encarregado') THEN RAISE EXCEPTION 'STOP_ENCARREGADO_SHARED_ADMIN_DEPENDENCY'; END IF;
 FOR f IN SELECT value FROM jsonb_array_elements($contract$EXPECTED$contract$::jsonb) LOOP
  IF to_regprocedure(f->>'signature') IS NULL OR encode(sha256(convert_to(replace(pg_get_functiondef(to_regprocedure(f->>'signature')),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM f->>'hash' THEN RAISE EXCEPTION 'FUNCTION_CONTRACT_DRIFT: %',f->>'signature'; END IF;
 END LOOP;
 IF position('DESPESAS_GERAIS_BLOQUEADAS' IN pg_get_functiondef('public.fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)'::regprocedure))=0 THEN RAISE EXCEPTION 'LEGACY_GENERAL_BRANCH_NOT_CLOSED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND p.prosrc ~* '\mdebitos_diretos(_lancamentos)?\M' AND p.proname<>'fn_importar_mapa_financeiro_xlsx') THEN RAISE EXCEPTION 'UNREVIEWED_DEBIT_CONSUMER'; END IF;
END $check$;
""".replace('EXPECTED',expected)
check+=catalog_check
check+=r"""
DO $functions$ DECLARE f jsonb; p record; actual text[]; expected_acl text[]; BEGIN
 FOR f IN SELECT value FROM jsonb_array_elements($function_json$FUNCTION_CONTRACT$function_json$::jsonb) LOOP
  SELECT * INTO STRICT p FROM pg_proc WHERE oid=to_regprocedure(f->>'signature');
  SELECT array_agg(x ORDER BY x) INTO actual FROM unnest(string_to_array(trim(both '{}' from coalesce(p.proacl,acldefault('f',p.proowner))::text),',')) x;
  SELECT array_agg(x ORDER BY x) INTO expected_acl FROM unnest(string_to_array(trim(both '{}' from coalesce(f->>'acl','{=X/postgres,postgres=X/postgres}')),',')) x;
  IF pg_get_userbyid(p.proowner) IS DISTINCT FROM f->>'owner' OR p.prosecdef IS DISTINCT FROM (f->>'security_definer')::boolean OR to_jsonb(p.proconfig) IS DISTINCT FROM nullif(f->'config','null'::jsonb) OR actual IS DISTINCT FROM expected_acl THEN RAISE EXCEPTION 'FUNCTION_ACL_OWNER_CONFIG_DRIFT: %',f->>'signature'; END IF;
 END LOOP;
END $functions$;
""".replace('FUNCTION_CONTRACT',function_contract)
start="BEGIN;\nSET LOCAL lock_timeout='10s';\nSET LOCAL search_path=public,pg_catalog;\nLOCK TABLE public.debitos_diretos,public.debitos_diretos_lancamentos IN ACCESS EXCLUSIVE MODE;\n"
def put(name,s): (root/'supabase'/('financeiro_debitos_tenant_20261011'+name+'.sql')).write_text(s,encoding='utf-8')
put('_precheck','-- READ ONLY. Any error is STOP; no automatic reconciliation.\nBEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSET LOCAL search_path=public,pg_catalog;\n'+check+"SELECT 'FINANCEIRO_DEBITOS_PRECHECK_OK' resultado;\nCOMMIT;\n")
backup=r"""
CREATE SCHEMA primeline_debitos_20261011 AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_debitos_20261011 FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_debitos_20261011.debitos AS TABLE public.debitos_diretos;
CREATE TABLE primeline_debitos_20261011.lancamentos AS TABLE public.debitos_diretos_lancamentos;
CREATE TABLE primeline_debitos_20261011.controlo(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),state text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),acl_debitos aclitem[],acl_lancamentos aclitem[],data_debitos jsonb,data_lancamentos jsonb);
INSERT INTO primeline_debitos_20261011.controlo(state,acl_debitos,acl_lancamentos,data_debitos,data_lancamentos)
SELECT 'prepared',(SELECT relacl FROM pg_class WHERE oid='public.debitos_diretos'::regclass),(SELECT relacl FROM pg_class WHERE oid='public.debitos_diretos_lancamentos'::regclass),
(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') FROM public.debitos_diretos d),
(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY id),'[]') FROM public.debitos_diretos_lancamentos l);
ALTER TABLE primeline_debitos_20261011.debitos ENABLE ROW LEVEL SECURITY;
ALTER TABLE primeline_debitos_20261011.lancamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE primeline_debitos_20261011.controlo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_debitos_20261011 FROM PUBLIC,anon,authenticated,service_role;
SELECT 'FINANCEIRO_DEBITOS_BACKUP_OK' resultado;
COMMIT;
"""
put('_backup',start+check+backup)
migration=r"""
DO $backup$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM primeline_debitos_20261011.controlo WHERE singleton AND state='prepared') THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF (SELECT data_debitos FROM primeline_debitos_20261011.controlo WHERE singleton) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') FROM public.debitos_diretos d) OR (SELECT data_lancamentos FROM primeline_debitos_20261011.controlo WHERE singleton) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY id),'[]') FROM public.debitos_diretos_lancamentos l) THEN RAISE EXCEPTION 'BACKUP_DATA_DRIFT'; END IF;
END $backup$;
ALTER TABLE public.debitos_diretos ADD COLUMN empresa_id uuid REFERENCES public.empresas(id);
ALTER TABLE public.debitos_diretos_lancamentos ADD COLUMN empresa_id uuid REFERENCES public.empresas(id);
-- Only A: an existing valid work FK and an existing company. No author inference.
UPDATE public.debitos_diretos d SET empresa_id=o.empresa_id FROM public.obras o JOIN public.empresas e ON e.id=o.empresa_id WHERE d.obra_id=o.id;
UPDATE public.debitos_diretos_lancamentos l SET empresa_id=d.empresa_id FROM public.debitos_diretos d WHERE d.id=l.debito_direto_id AND d.empresa_id IS NOT NULL;
-- NOT VALID preserves unresolved historical rows; every new/updated row is checked.
ALTER TABLE public.debitos_diretos ADD CONSTRAINT dd_empresa_nova_obrigatoria CHECK(empresa_id IS NOT NULL) NOT VALID;
ALTER TABLE public.debitos_diretos_lancamentos ADD CONSTRAINT ddl_empresa_nova_obrigatoria CHECK(empresa_id IS NOT NULL) NOT VALID;
CREATE UNIQUE INDEX dd_id_empresa_unique ON public.debitos_diretos(id,empresa_id);
ALTER TABLE public.debitos_diretos_lancamentos ADD CONSTRAINT ddl_parent_empresa FOREIGN KEY(debito_direto_id,empresa_id) REFERENCES public.debitos_diretos(id,empresa_id);
CREATE SCHEMA financeiro_debitos_privado AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA financeiro_debitos_privado FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE financeiro_debitos_privado.config(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),secret bytea NOT NULL);
INSERT INTO financeiro_debitos_privado.config(secret) VALUES(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text,'UTF8')));
CREATE TABLE financeiro_debitos_privado.grupos(empresa_id uuid NOT NULL REFERENCES public.empresas(id),categoria text NOT NULL,debito_id uuid NOT NULL UNIQUE,PRIMARY KEY(empresa_id,categoria),FOREIGN KEY(debito_id,empresa_id) REFERENCES public.debitos_diretos(id,empresa_id));
CREATE TABLE financeiro_debitos_privado.operacoes(request_id uuid PRIMARY KEY,empresa_id uuid NOT NULL,ator_id uuid NOT NULL,payload jsonb NOT NULL,result jsonb NOT NULL,changes jsonb NOT NULL,created_debits jsonb NOT NULL,at timestamptz NOT NULL DEFAULT clock_timestamp(),reversed_at timestamptz,reverse_request_id uuid UNIQUE,reverse_actor_id uuid,reverse_reason text);
CREATE FUNCTION financeiro_debitos_privado.ator() RETURNS public.utilizadores LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE u public.utilizadores; BEGIN
 IF (SELECT count(*) FROM public.utilizadores WHERE auth_user_id=auth.uid() AND ativo IS TRUE)<>1 THEN RAISE EXCEPTION 'FORBIDDEN: sessão indisponível' USING ERRCODE='42501'; END IF;
 u:=public.fn_economico_ator_atual();
 IF u.funcao IS NULL OR u.funcao NOT IN('gestao_plataforma','gerencia','administrativo','financeiro') OR NOT(public.fn_e_administrativo() OR public.fn_e_financeiro()) THEN RAISE EXCEPTION 'FORBIDDEN: perfil sem permissão financeira' USING ERRCODE='42501'; END IF;
 RETURN u;
END $fn$;
CREATE FUNCTION public.fn_debitos_tenant_leitura(p_empresa uuid,p_obra uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT p_empresa IS NOT NULL AND (SELECT count(*) FROM public.utilizadores WHERE auth_user_id=auth.uid() AND ativo IS TRUE)=1 AND EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.auth_user_id=auth.uid() AND u.ativo IS TRUE AND u.empresa_id=p_empresa)
 AND (public.fn_e_administrativo() OR public.fn_e_financeiro() OR (p_obra IS NOT NULL AND public.fn_pode_ver_obra(p_obra)))
 AND (p_obra IS NULL OR EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra AND o.empresa_id=p_empresa));
$fn$;
CREATE FUNCTION financeiro_debitos_privado.guarda() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE u public.utilizadores; d public.debitos_diretos; company uuid; BEGIN
 u:=financeiro_debitos_privado.ator();
 IF TG_OP='DELETE' THEN
  IF OLD.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'FORBIDDEN: entidade indisponível' USING ERRCODE='42501'; END IF;
  RETURN OLD;
 END IF;
 IF NEW.empresa_id IS NOT NULL AND NEW.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'FORBIDDEN: empresa inválida' USING ERRCODE='42501'; END IF;
 IF TG_OP='UPDATE' AND (OLD.empresa_id IS NULL OR OLD.empresa_id IS DISTINCT FROM u.empresa_id OR NEW.id IS DISTINCT FROM OLD.id OR NEW.empresa_id IS DISTINCT FROM OLD.empresa_id) THEN RAISE EXCEPTION 'FORBIDDEN: identidade/tenant imutável' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='debitos_diretos' THEN
  IF NEW.obra_id IS NOT NULL THEN
   SELECT empresa_id INTO company FROM public.obras WHERE id=NEW.obra_id FOR SHARE;
   IF company IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'FORBIDDEN: obra indisponível' USING ERRCODE='42501'; END IF;
  END IF;
  IF TG_OP='INSERT' THEN
   IF NEW.criado_por IS NOT NULL AND NEW.criado_por IS DISTINCT FROM u.id THEN RAISE EXCEPTION 'FORBIDDEN: autor inválido' USING ERRCODE='42501'; END IF;
   NEW.criado_por:=u.id; NEW.criado_em:=clock_timestamp();
  END IF;
 ELSE
  SELECT * INTO d FROM public.debitos_diretos WHERE id=NEW.debito_direto_id FOR SHARE;
  IF d.id IS NULL OR d.empresa_id IS DISTINCT FROM u.empresa_id OR NOT public.fn_debitos_tenant_leitura(d.empresa_id,d.obra_id) THEN RAISE EXCEPTION 'FORBIDDEN: débito indisponível' USING ERRCODE='42501'; END IF;
  IF TG_OP='UPDATE' AND NEW.debito_direto_id IS DISTINCT FROM OLD.debito_direto_id THEN RAISE EXCEPTION 'FORBIDDEN: débito imutável' USING ERRCODE='42501'; END IF;
 END IF;
 NEW.empresa_id:=u.empresa_id; RETURN NEW;
END $fn$;
CREATE TRIGGER trg_00_dd_tenant BEFORE INSERT OR UPDATE OR DELETE ON public.debitos_diretos FOR EACH ROW EXECUTE FUNCTION financeiro_debitos_privado.guarda();
CREATE TRIGGER trg_00_ddl_tenant BEFORE INSERT OR UPDATE OR DELETE ON public.debitos_diretos_lancamentos FOR EACH ROW EXECUTE FUNCTION financeiro_debitos_privado.guarda();
CREATE POLICY dd_tenant_restrito ON public.debitos_diretos AS RESTRICTIVE FOR ALL TO authenticated USING(public.fn_debitos_tenant_leitura(empresa_id,obra_id)) WITH CHECK(public.fn_debitos_tenant_leitura(empresa_id,obra_id));
CREATE POLICY ddl_tenant_restrito ON public.debitos_diretos_lancamentos AS RESTRICTIVE FOR ALL TO authenticated USING(empresa_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.debitos_diretos d WHERE d.id=debito_direto_id AND d.empresa_id=debitos_diretos_lancamentos.empresa_id)) WITH CHECK(empresa_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.debitos_diretos d WHERE d.id=debito_direto_id AND d.empresa_id=debitos_diretos_lancamentos.empresa_id));
REVOKE ALL ON public.debitos_diretos,public.debitos_diretos_lancamentos FROM anon,service_role;
-- Existing authenticated SELECT/INSERT and role policies remain. No generic UPDATE/DELETE grant.
CREATE FUNCTION financeiro_debitos_privado.mac(p_text text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE key bytea; inner_pad bytea:=decode(repeat('36',64),'hex'); outer_pad bytea:=decode(repeat('5c',64),'hex'); i integer; BEGIN
 SELECT secret INTO STRICT key FROM financeiro_debitos_privado.config WHERE singleton;
 -- RFC 2104 HMAC-SHA256; the generated key is exactly 32 bytes.
 FOR i IN 0..31 LOOP
  inner_pad:=set_byte(inner_pad,i,get_byte(inner_pad,i)#get_byte(key,i));
  outer_pad:=set_byte(outer_pad,i,get_byte(outer_pad,i)#get_byte(key,i));
 END LOOP;
 RETURN encode(sha256(outer_pad||sha256(inner_pad||convert_to(p_text,'UTF8'))),'hex');
END $fn$;
CREATE FUNCTION financeiro_debitos_privado.snapshot(p_empresa uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT jsonb_build_object(
  'debits',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id),'[]') FROM public.debitos_diretos d WHERE d.empresa_id=p_empresa),
  'entries',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY l.id),'[]') FROM public.debitos_diretos_lancamentos l WHERE l.empresa_id=p_empresa),
  'groups',(SELECT coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.categoria),'[]') FROM financeiro_debitos_privado.grupos g WHERE g.empresa_id=p_empresa),
  'adjustments',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.id),'[]') FROM public.mapa_financeiro_ajustes a JOIN public.obras o ON o.id=a.obra_id WHERE o.empresa_id=p_empresa));
$fn$;
"""
put('',start+check+migration)
imports=r"""
CREATE FUNCTION public.fn_despesas_gerais_importar_v1(p_ano integer,p_linhas jsonb,p_nome_ficheiro text,p_request_id uuid,p_confirmar boolean DEFAULT false,p_preview_token text DEFAULT NULL,p_substituir boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE u public.utilizadores; op financeiro_debitos_privado.operacoes; payload jsonb; before_state jsonb; after_state jsonb; token text; report jsonb:='[]'; errors jsonb; line jsonb; val jsonb; idx integer:=0; month integer; valid integer:=0; invalid integer:=0; duplicates integer:=0; changed integer:=0; did uuid; wid uuid; oldvalue numeric; seen text[]:=ARRAY[]::text[]; key text; any_change boolean; work_lines jsonb:='[]'; result jsonb; changes jsonb; created jsonb:='[]'; table_key text;
BEGIN
 u:=financeiro_debitos_privado.ator();
 IF p_request_id IS NULL OR p_ano IS NULL OR p_ano NOT BETWEEN 2000 AND 2200 OR jsonb_typeof(p_linhas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_linhas) NOT BETWEEN 1 AND 1000 OR length(p_linhas::text)>2000000 OR p_nome_ficheiro IS NULL OR length(btrim(p_nome_ficheiro)) NOT BETWEEN 1 AND 255 OR p_substituir IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: formato da importação inválido' USING ERRCODE='22023'; END IF;
 payload:=jsonb_build_object('ano',p_ano,'linhas',p_linhas,'ficheiro',p_nome_ficheiro,'substituir',p_substituir);
 IF NOT(public.fn_e_admin() OR public.fn_e_financeiro()) THEN RAISE EXCEPTION 'FORBIDDEN: perfil sem permissão de importação no contrato atual' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('debitos-import:'||p_request_id::text,0));
 SELECT * INTO op FROM financeiro_debitos_privado.operacoes WHERE request_id=p_request_id;
 IF FOUND THEN
  IF op.empresa_id IS DISTINCT FROM u.empresa_id OR op.ator_id IS DISTINCT FROM u.id THEN RAISE EXCEPTION 'FORBIDDEN: operação indisponível' USING ERRCODE='42501'; END IF;
  IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE='22023'; END IF;
  IF op.reversed_at IS NOT NULL THEN RAISE EXCEPTION 'IMPORT_REVERTED: use uma nova operação revista' USING ERRCODE='22023'; END IF;
  RETURN op.result||jsonb_build_object('replay',true);
 END IF;
 IF p_confirmar IS TRUE THEN
  -- Serializes all affected financial facts while rechecking the preview snapshot.
  LOCK TABLE public.debitos_diretos,public.debitos_diretos_lancamentos,public.mapa_financeiro_ajustes,financeiro_debitos_privado.grupos IN SHARE ROW EXCLUSIVE MODE;
 END IF;
 before_state:=financeiro_debitos_privado.snapshot(u.empresa_id);
 FOR line IN SELECT value FROM jsonb_array_elements(p_linhas) LOOP
  idx:=idx+1; errors:='[]'; any_change:=false; did:=NULL; wid:=NULL;
  IF jsonb_typeof(line) IS DISTINCT FROM 'object' THEN errors:=errors||jsonb_build_array('Linha inválida.');
  ELSE
   IF line ? 'empresa_id' OR line ? 'criado_por' THEN RAISE EXCEPTION 'FORBIDDEN: tenant e autor são determinados pelo servidor' USING ERRCODE='42501'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(line) k WHERE k NOT IN('tipo','obra_id','categoria','meses','linha')) THEN errors:=errors||jsonb_build_array('Campo não suportado.'); END IF;
   IF line->>'tipo'='despesa_fixa' THEN
    key:='categoria:'||coalesce(line->>'categoria','');
    IF line->>'categoria' IS NULL OR line->>'categoria' NOT IN('remuneracoes_sede','despesas_sede','despesas_armazem') OR line ? 'obra_id' THEN errors:=errors||jsonb_build_array('Categoria de despesas gerais inválida.'); END IF;
    SELECT g.debito_id INTO did FROM financeiro_debitos_privado.grupos g JOIN public.debitos_diretos d ON d.id=g.debito_id AND d.empresa_id=g.empresa_id WHERE g.empresa_id=u.empresa_id AND g.categoria=line->>'categoria';
    IF EXISTS(SELECT 1 FROM public.debitos_diretos d WHERE d.empresa_id=u.empresa_id AND d.obra_id IS NULL AND d.categoria=line->>'categoria' AND NOT EXISTS(SELECT 1 FROM financeiro_debitos_privado.grupos g WHERE g.debito_id=d.id AND g.empresa_id=u.empresa_id)) THEN errors:=errors||jsonb_build_array('Categoria com débitos individuais: reconciliação explícita necessária antes de importar; nenhuma consolidação automática.'); END IF;
   ELSIF line->>'tipo'='obra' THEN
    IF NOT(public.fn_e_admin() OR public.fn_e_financeiro()) THEN RAISE EXCEPTION 'FORBIDDEN: perfil sem importação por obra no contrato atual' USING ERRCODE='42501'; END IF;
    BEGIN wid:=nullif(line->>'obra_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN errors:=errors||jsonb_build_array('UUID da obra inválido.'); END;
    key:='obra:'||coalesce(wid::text,'');
    IF wid IS NOT NULL THEN PERFORM public.fn_financeiro_autorizar_obra(wid,false); ELSE errors:=errors||jsonb_build_array('Obra obrigatória.'); END IF;
    IF line ? 'categoria' THEN errors:=errors||jsonb_build_array('Categoria incompatível com linha de obra.'); END IF;
   ELSE key:='invalid:'||idx; errors:=errors||jsonb_build_array('Tipo de linha inválido.'); END IF;
   IF key=ANY(seen) THEN errors:=errors||jsonb_build_array('Chave repetida no próprio ficheiro; consolide antes de importar.'); END IF;
   seen:=array_append(seen,key);
   IF jsonb_typeof(line->'meses') IS DISTINCT FROM 'array' OR jsonb_array_length(line->'meses')<>12 THEN errors:=errors||jsonb_build_array('São obrigatórios 12 meses, com número ou null.');
   ELSE
    month:=0;
    FOR val IN SELECT value FROM jsonb_array_elements(line->'meses') LOOP
     month:=month+1; oldvalue:=NULL;
     IF jsonb_typeof(val) NOT IN('number','null') THEN errors:=errors||jsonb_build_array('Mês '||month||': valor numérico inválido.');
     ELSIF jsonb_typeof(val)='number' THEN
      IF line->>'tipo'='obra' THEN SELECT valor_ajustado INTO oldvalue FROM public.mapa_financeiro_ajustes WHERE obra_id=wid AND ano=p_ano AND mes=month;
      ELSE SELECT valor INTO oldvalue FROM public.debitos_diretos_lancamentos WHERE debito_direto_id=did AND data=make_date(p_ano,month,1); END IF;
      IF oldvalue IS DISTINCT FROM (val#>>'{}')::numeric THEN
       any_change:=true;
       IF oldvalue IS NOT NULL AND NOT p_substituir THEN errors:=errors||jsonb_build_array('Mês '||month||': já existe outro valor; substituição exige confirmação explícita.'); END IF;
      END IF;
     END IF;
    END LOOP;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(line->'meses') v WHERE jsonb_typeof(v)='number') THEN errors:=errors||jsonb_build_array('Linha sem valores mensais.'); END IF;
   END IF;
  END IF;
  IF jsonb_array_length(errors)>0 THEN invalid:=invalid+1;
  ELSIF any_change THEN valid:=valid+1;
  ELSE duplicates:=duplicates+1; END IF;
  report:=report||jsonb_build_array(jsonb_build_object('linha',idx,'tipo',line->>'tipo','categoria',line->>'categoria','obra_id',wid,'estado',CASE WHEN jsonb_array_length(errors)>0 THEN 'invalid' WHEN any_change THEN 'valid' ELSE 'duplicate' END,'erros',errors));
 END LOOP;
 token:=financeiro_debitos_privado.mac(jsonb_build_object('kind','import','actor',u.id,'company',u.empresa_id,'request',p_request_id,'payload',payload,'before',before_state)::text);
 result:=jsonb_build_object('version',1,'request_id',p_request_id,'committed',false,'validas',valid,'invalidas',invalid,'duplicadas',duplicates,'linhas',report,'preview_token',token,'substituir',p_substituir);
 IF p_confirmar IS DISTINCT FROM true THEN RETURN result; END IF;
 IF invalid<>0 THEN RAISE EXCEPTION 'IMPORT_VALIDATION_FAILED: nenhuma linha foi gravada' USING ERRCODE='22023',DETAIL=result::text; END IF;
 IF p_preview_token IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW: recarregue a validação' USING ERRCODE='40001'; END IF;
 idx:=0;
 FOR line IN SELECT value FROM jsonb_array_elements(p_linhas) LOOP
  idx:=idx+1;
  IF report->(idx-1)->>'estado'='duplicate' THEN CONTINUE; END IF;
  IF line->>'tipo'='obra' THEN work_lines:=work_lines||jsonb_build_array(line-'linha'); CONTINUE; END IF;
  SELECT debito_id INTO did FROM financeiro_debitos_privado.grupos WHERE empresa_id=u.empresa_id AND categoria=line->>'categoria';
  IF did IS NULL THEN
   INSERT INTO public.debitos_diretos(obra_id,descricao,categoria,valor_previsto,recorrencia,dia_mes,data_inicio,ativo,criado_por)
   VALUES(NULL,'Importação Mapa Financeiro · '||(line->>'categoria'),line->>'categoria',0,'mensal',1,make_date(p_ano,1,1),true,u.id) RETURNING id INTO did;
   INSERT INTO financeiro_debitos_privado.grupos VALUES(u.empresa_id,line->>'categoria',did);
   created:=created||jsonb_build_array(did);
  END IF;
  month:=0;
  FOR val IN SELECT value FROM jsonb_array_elements(line->'meses') LOOP
   month:=month+1;
   IF jsonb_typeof(val)='number' THEN
    INSERT INTO public.debitos_diretos_lancamentos(debito_direto_id,data,valor)
    VALUES(did,make_date(p_ano,month,1),(val#>>'{}')::numeric)
    ON CONFLICT(debito_direto_id,data) DO UPDATE SET valor=EXCLUDED.valor;
   END IF;
  END LOOP;
  changed:=changed+1;
 END LOOP;
 IF jsonb_array_length(work_lines)>0 THEN PERFORM public.fn_importar_mapa_financeiro_xlsx(p_ano,work_lines,p_nome_ficheiro); changed:=changed+jsonb_array_length(work_lines); END IF;
 after_state:=financeiro_debitos_privado.snapshot(u.empresa_id);
 changes:='[]';
 FOREACH table_key IN ARRAY ARRAY['debits','entries','adjustments'] LOOP
  changes:=changes||coalesce((SELECT jsonb_agg(jsonb_build_object('table',table_key,'id',a->>'id','before',b,'after',a) ORDER BY a->>'id')
   FROM jsonb_array_elements(after_state->table_key) a
   LEFT JOIN jsonb_array_elements(before_state->table_key) b ON a->>'id'=b->>'id'
   WHERE a IS DISTINCT FROM b),'[]'::jsonb);
 END LOOP;
 result:=result-'preview_token'||jsonb_build_object('committed',true,'importadas',changed,'replay',false);
 INSERT INTO financeiro_debitos_privado.operacoes(request_id,empresa_id,ator_id,payload,result,changes,created_debits) VALUES(p_request_id,u.empresa_id,u.id,payload,result,changes,created);
 PERFORM public.fn_log_importacao_xlsx('despesas_gerais_tenant',p_nome_ficheiro,changed,jsonb_build_object('ano',p_ano,'request_id',p_request_id,'duplicadas',duplicates));
 RETURN result;
END $fn$;

CREATE FUNCTION public.fn_despesas_gerais_reverter_v1(p_import_request_id uuid,p_request_id uuid,p_motivo text,p_confirmar boolean DEFAULT false,p_preview_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE u public.utilizadores; op financeiro_debitos_privado.operacoes; c jsonb; current_row jsonb; token text; result jsonb; did uuid; BEGIN
 u:=financeiro_debitos_privado.ator();
 IF p_request_id IS NULL OR p_import_request_id IS NULL OR p_request_id=p_import_request_id OR length(btrim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 1000 THEN RAISE EXCEPTION 'VALIDATION_ERROR: motivo e request_id novos obrigatórios' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('debitos-revert:'||p_request_id::text,0));
 IF NOT(public.fn_e_admin() OR public.fn_e_financeiro()) THEN RAISE EXCEPTION 'FORBIDDEN: perfil sem permissão de reversão de importação' USING ERRCODE='42501'; END IF;
 SELECT * INTO op FROM financeiro_debitos_privado.operacoes WHERE request_id=p_import_request_id FOR UPDATE;
 IF op.request_id IS NULL OR op.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'FORBIDDEN: importação indisponível' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM financeiro_debitos_privado.operacoes WHERE request_id=p_request_id OR (reverse_request_id=p_request_id AND request_id<>p_import_request_id)) THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE='22023'; END IF;
 IF op.reversed_at IS NOT NULL THEN
  IF op.reverse_request_id=p_request_id AND op.reverse_actor_id=u.id AND op.reverse_reason=p_motivo THEN RETURN jsonb_build_object('committed',true,'reversed',true,'replay',true,'request_id',p_request_id); END IF;
  RAISE EXCEPTION 'IMPORT_ALREADY_REVERTED' USING ERRCODE='22023';
 END IF;
 IF p_confirmar IS TRUE THEN LOCK TABLE public.debitos_diretos,public.debitos_diretos_lancamentos,public.mapa_financeiro_ajustes,financeiro_debitos_privado.grupos IN SHARE ROW EXCLUSIVE MODE; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(op.changes) LOOP
  IF c->>'table'='debits' THEN SELECT to_jsonb(d) INTO current_row FROM public.debitos_diretos d WHERE id=(c->>'id')::uuid AND empresa_id=u.empresa_id;
  ELSIF c->>'table'='entries' THEN SELECT to_jsonb(l) INTO current_row FROM public.debitos_diretos_lancamentos l WHERE id=(c->>'id')::uuid AND empresa_id=u.empresa_id;
  ELSIF c->>'table'='adjustments' THEN PERFORM public.fn_financeiro_autorizar_obra((c->'after'->>'obra_id')::uuid,false); SELECT to_jsonb(a) INTO current_row FROM public.mapa_financeiro_ajustes a WHERE id=(c->>'id')::uuid;
  ELSE RAISE EXCEPTION 'AUDIT_CONTRACT_ERROR'; END IF;
  IF current_row IS DISTINCT FROM c->'after' THEN RAISE EXCEPTION 'STALE_IMPORT: um objeto foi alterado posteriormente' USING ERRCODE='40001'; END IF;
 END LOOP;
 FOR did IN SELECT value::text::uuid FROM jsonb_array_elements_text(op.created_debits) LOOP
  IF EXISTS(SELECT 1 FROM public.debitos_diretos_lancamentos l WHERE l.debito_direto_id=did AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(op.changes) child WHERE child->>'table'='entries' AND child->>'id'=l.id::text)) THEN RAISE EXCEPTION 'STALE_IMPORT: existem lançamentos posteriores' USING ERRCODE='40001'; END IF;
 END LOOP;
 token:=financeiro_debitos_privado.mac(jsonb_build_object('kind','revert','actor',u.id,'company',u.empresa_id,'request',p_request_id,'import',p_import_request_id,'reason',p_motivo,'operation',to_jsonb(op),'snapshot',financeiro_debitos_privado.snapshot(u.empresa_id))::text);
 result:=jsonb_build_object('committed',false,'request_id',p_request_id,'import_request_id',p_import_request_id,'objetos',jsonb_array_length(op.changes),'preview_token',token);
 IF p_confirmar IS DISTINCT FROM true THEN RETURN result; END IF;
 IF p_preview_token IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW: reveja a reversão' USING ERRCODE='40001'; END IF;
 -- Reverse children first. Existing historical facts are restored only if still equal to the recorded after-image.
 FOR c IN SELECT value FROM jsonb_array_elements(op.changes) WHERE value->>'table'='entries' LOOP
  IF c->'before'='null'::jsonb THEN DELETE FROM public.debitos_diretos_lancamentos WHERE id=(c->>'id')::uuid;
  ELSE UPDATE public.debitos_diretos_lancamentos SET valor=(c->'before'->>'valor')::numeric WHERE id=(c->>'id')::uuid; END IF;
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(op.changes) WHERE value->>'table'='adjustments' LOOP
  IF c->'before'='null'::jsonb THEN DELETE FROM public.mapa_financeiro_ajustes WHERE id=(c->>'id')::uuid;
  ELSE UPDATE public.mapa_financeiro_ajustes SET valor_ajustado=(c->'before'->>'valor_ajustado')::numeric,motivo=c->'before'->>'motivo',atualizado_por=(c->'before'->>'atualizado_por')::uuid,atualizado_em=(c->'before'->>'atualizado_em')::timestamptz WHERE id=(c->>'id')::uuid; END IF;
 END LOOP;
 FOR did IN SELECT value::text::uuid FROM jsonb_array_elements_text(op.created_debits) LOOP
  DELETE FROM financeiro_debitos_privado.grupos WHERE debito_id=did AND empresa_id=u.empresa_id;
  DELETE FROM public.debitos_diretos WHERE id=did AND empresa_id=u.empresa_id;
 END LOOP;
 UPDATE financeiro_debitos_privado.operacoes SET reversed_at=clock_timestamp(),reverse_request_id=p_request_id,reverse_actor_id=u.id,reverse_reason=p_motivo WHERE request_id=p_import_request_id;
 PERFORM public.fn_log_importacao_xlsx('despesas_gerais_reversao','reversão controlada',jsonb_array_length(op.changes),jsonb_build_object('request_id',p_request_id,'import_request_id',p_import_request_id,'motivo',p_motivo));
 RETURN result-'preview_token'||jsonb_build_object('committed',true,'reversed',true,'replay',false);
END $fn$;

ALTER TABLE financeiro_debitos_privado.config ENABLE ROW LEVEL SECURITY;
ALTER TABLE financeiro_debitos_privado.grupos ENABLE ROW LEVEL SECURITY;
ALTER TABLE financeiro_debitos_privado.operacoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA financeiro_debitos_privado FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA financeiro_debitos_privado FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_debitos_tenant_leitura(uuid,uuid),public.fn_despesas_gerais_importar_v1(integer,jsonb,text,uuid,boolean,text,boolean),public.fn_despesas_gerais_reverter_v1(uuid,uuid,text,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_debitos_tenant_leitura(uuid,uuid),public.fn_despesas_gerais_importar_v1(integer,jsonb,text,uuid,boolean,text,boolean),public.fn_despesas_gerais_reverter_v1(uuid,uuid,text,boolean,text) TO authenticated;
UPDATE primeline_debitos_20261011.controlo SET state='applied' WHERE singleton;
SELECT 'FINANCEIRO_DEBITOS_MIGRATION_OK' resultado;
COMMIT;
"""
put('',start+check+migration+imports)
post=r"""
-- Read-only, immediately after installation and before opening financial writes.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=public,pg_catalog;
DO $post$ DECLARE rel regclass; n text; f jsonb; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_debitos_20261011.controlo WHERE singleton AND state='applied') THEN RAISE EXCEPTION 'APPLIED_BACKUP_REQUIRED'; END IF;
 IF (SELECT data_debitos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(d)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos d) OR (SELECT data_lancamentos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(l)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos_lancamentos l) THEN RAISE EXCEPTION 'HISTORICAL_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.debitos_diretos d LEFT JOIN public.obras o ON o.id=d.obra_id LEFT JOIN public.empresas e ON e.id=o.empresa_id WHERE d.empresa_id IS DISTINCT FROM e.id) OR EXISTS(SELECT 1 FROM public.debitos_diretos_lancamentos l JOIN public.debitos_diretos d ON d.id=l.debito_direto_id WHERE l.empresa_id IS DISTINCT FROM d.empresa_id) THEN RAISE EXCEPTION 'BACKFILL_NOT_EXCLUSIVELY_A'; END IF;
 FOREACH n IN ARRAY ARRAY['debitos_diretos','debitos_diretos_lancamentos'] LOOP
  rel:=('public.'||n)::regclass;
  IF NOT (SELECT relrowsecurity AND relowner='postgres'::regrole FROM pg_class WHERE oid=rel) THEN RAISE EXCEPTION 'OWNER_RLS_DRIFT'; END IF;
  IF NOT has_table_privilege('authenticated',rel,'SELECT') OR NOT has_table_privilege('authenticated',rel,'INSERT') OR has_table_privilege('authenticated',rel,'UPDATE,DELETE,TRUNCATE') OR has_table_privilege('anon',rel,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('service_role',rel,'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'TARGET_ACL_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=rel AND attnum>0 AND attacl IS NOT NULL) THEN RAISE EXCEPTION 'COLUMN_ACL_DRIFT'; END IF;
  IF (SELECT count(*) FROM pg_policy WHERE polrelid=rel AND NOT polpermissive AND polcmd='*')<>1 OR (SELECT count(*) FROM pg_policy WHERE polrelid=rel)<>3 THEN RAISE EXCEPTION 'TENANT_POLICY_MISSING'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=rel AND NOT tgisinternal AND tgname=CASE WHEN n='debitos_diretos' THEN 'trg_00_dd_tenant' ELSE 'trg_00_ddl_tenant' END AND tgenabled='O' AND tgfoid='financeiro_debitos_privado.guarda()'::regprocedure) THEN RAISE EXCEPTION 'TENANT_GUARD_MISSING'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=rel AND NOT tgisinternal AND tgname='trg_auditoria_'||n AND tgenabled='O' AND tgfoid='public.fn_registar_log_auditoria()'::regprocedure) THEN RAISE EXCEPTION 'AUDIT_MISSING'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_namespace WHERE nspname IN('financeiro_debitos_privado','primeline_debitos_20261011') AND (nspowner<>'postgres'::regrole OR has_schema_privilege('authenticated',oid,'USAGE') OR has_schema_privilege('anon',oid,'USAGE') OR has_schema_privilege('service_role',oid,'USAGE'))) THEN RAISE EXCEPTION 'PRIVATE_SCHEMA_EXPOSED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('financeiro_debitos_privado','primeline_debitos_20261011') AND c.relkind='r' AND (NOT c.relrowsecurity OR has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE'))) THEN RAISE EXCEPTION 'PRIVATE_TABLE_EXPOSED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='financeiro_debitos_privado' AND (has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'))) THEN RAISE EXCEPTION 'PRIVATE_FUNCTION_EXPOSED'; END IF;
 FOR f IN SELECT value FROM jsonb_array_elements($contract$EXPECTED$contract$::jsonb) LOOP
  IF encode(sha256(convert_to(replace(pg_get_functiondef(to_regprocedure(f->>'signature')),chr(13),''),'UTF8')),'hex') IS DISTINCT FROM f->>'hash' THEN RAISE EXCEPTION 'UNRELATED_HELPER_CHANGED: %',f->>'signature'; END IF;
 END LOOP;
 FOREACH n IN ARRAY ARRAY['fn_debitos_tenant_leitura(uuid,uuid)','fn_despesas_gerais_importar_v1(integer,jsonb,text,uuid,boolean,text,boolean)','fn_despesas_gerais_reverter_v1(uuid,uuid,text,boolean,text)'] LOOP
  IF NOT has_function_privilege('authenticated',n,'EXECUTE') OR has_function_privilege('anon',n,'EXECUTE') OR has_function_privilege('service_role',n,'EXECUTE') OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=n::regprocedure AND prosecdef AND proowner='postgres'::regrole AND proconfig=ARRAY['search_path=pg_catalog']) THEN RAISE EXCEPTION 'PUBLIC_RPC_CONTRACT_DRIFT: %',n; END IF;
 END LOOP;
END $post$;
SELECT 'FINANCEIRO_DEBITOS_POSTCHECK_OK' resultado;
COMMIT;
""".replace('EXPECTED',expected)
sources=[{'name':m.group(1),'sha256':hashlib.sha256(m.group(2).encode('utf-8')).hexdigest()} for m in re.finditer(r'CREATE FUNCTION ([a-z0-9_.]+)\([^)]*\)[\s\S]*?AS \$fn\$([\s\S]*?)\$fn\$;',migration+imports)]
assert len(sources)==7, 'All seven new public/private functions must be fingerprinted'
source_check=r"""
DO $source_check$ DECLARE f jsonb; BEGIN
 FOR f IN SELECT value FROM jsonb_array_elements($sources$SOURCE_CONTRACT$sources$::jsonb) LOOP
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname||'.'||p.proname=f->>'name')<>1 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname||'.'||p.proname=f->>'name' AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(p.prosrc,chr(13),''),'UTF8')),'hex')=f->>'sha256') THEN RAISE EXCEPTION 'NEW_FUNCTION_SOURCE_DRIFT: %',f->>'name'; END IF;
 END LOOP;
END $source_check$;
""".replace('SOURCE_CONTRACT',json.dumps(sources))
# Retain exact column types/defaults, original role policies, FKs/checks and audit triggers.
post_catalog=catalog_check
post_catalog=re.sub(r"  IF \(SELECT array_agg\(x ORDER BY x\)[^\n]+TABLE_ACL_DRIFT[^\n]+\n",'',post_catalog)
post_catalog=post_catalog.replace("<>jsonb_array_length(t->'policies')","<>jsonb_array_length(t->'policies')+1")
post_catalog=post_catalog.replace("<>jsonb_array_length(t->'constraints')","<>jsonb_array_length(t->'constraints')+(CASE WHEN t->>'name'='debitos_diretos' THEN 2 ELSE 3 END)")
post_catalog=post_catalog.replace("<>jsonb_array_length(t->'triggers')","<>jsonb_array_length(t->'triggers')+1")
post=post.replace("SELECT 'FINANCEIRO_DEBITOS_POSTCHECK_OK'",post_catalog+source_check+"SELECT 'FINANCEIRO_DEBITOS_POSTCHECK_OK'")
parent_qual='((empresa_id IS NOT NULL) AND (EXISTS ( SELECT 1\n   FROM debitos_diretos d\n  WHERE ((d.id = debitos_diretos_lancamentos.debito_direto_id) AND (d.empresa_id = debitos_diretos_lancamentos.empresa_id)))))'
policy_sources=[{'schemaname':'public','tablename':table,'policyname':name,'permissive':'RESTRICTIVE','roles':['authenticated'],'cmd':'ALL','qual':qual,'with_check':qual} for table,name,qual in [('debitos_diretos','dd_tenant_restrito','fn_debitos_tenant_leitura(empresa_id, obra_id)'),('debitos_diretos_lancamentos','ddl_tenant_restrito',parent_qual)]]
policy_check=r"""
DO $policies$ DECLARE expected jsonb; actual jsonb; BEGIN
 FOR expected IN SELECT value FROM jsonb_array_elements($policy_json$POLICY_SOURCES$policy_json$::jsonb) LOOP
  SELECT to_jsonb(v) INTO actual FROM pg_policies v WHERE schemaname='public' AND tablename=expected->>'tablename' AND policyname=expected->>'policyname';
  IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'TENANT_POLICY_DEFINITION_DRIFT: %',expected->>'policyname'; END IF;
 END LOOP;
END $policies$;
""".replace('POLICY_SOURCES',json.dumps(policy_sources))
post=post.replace("SELECT 'FINANCEIRO_DEBITOS_POSTCHECK_OK'",policy_check+"SELECT 'FINANCEIRO_DEBITOS_POSTCHECK_OK'")
put('_postcheck',post)
rollback=r"""
-- MANUAL ONLY. Installation rollback is forbidden after any new financial fact/import.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=public,pg_catalog;
LOCK TABLE public.debitos_diretos,public.debitos_diretos_lancamentos,financeiro_debitos_privado.operacoes,financeiro_debitos_privado.grupos IN ACCESS EXCLUSIVE MODE;
DO $stop$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_debitos_20261011.controlo WHERE state='applied' AND singleton) THEN RAISE EXCEPTION 'APPLIED_BACKUP_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM financeiro_debitos_privado.operacoes) OR EXISTS(SELECT 1 FROM financeiro_debitos_privado.grupos) THEN RAISE EXCEPTION 'STOP_NEW_FINANCIAL_OPERATIONS'; END IF;
 IF (SELECT data_debitos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(d)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos d) OR (SELECT data_lancamentos FROM primeline_debitos_20261011.controlo) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(l)-'empresa_id' ORDER BY id),'[]') FROM public.debitos_diretos_lancamentos l) THEN RAISE EXCEPTION 'STOP_NEW_OR_CHANGED_FINANCIAL_FACTS'; END IF;
END $stop$;
DROP FUNCTION public.fn_despesas_gerais_reverter_v1(uuid,uuid,text,boolean,text);
DROP FUNCTION public.fn_despesas_gerais_importar_v1(integer,jsonb,text,uuid,boolean,text,boolean);
DROP POLICY ddl_tenant_restrito ON public.debitos_diretos_lancamentos;
DROP POLICY dd_tenant_restrito ON public.debitos_diretos;
DROP TRIGGER trg_00_ddl_tenant ON public.debitos_diretos_lancamentos;
DROP TRIGGER trg_00_dd_tenant ON public.debitos_diretos;
DROP FUNCTION financeiro_debitos_privado.guarda();
DROP FUNCTION public.fn_debitos_tenant_leitura(uuid,uuid);
DROP FUNCTION financeiro_debitos_privado.snapshot(uuid);
DROP FUNCTION financeiro_debitos_privado.mac(text);
DROP FUNCTION financeiro_debitos_privado.ator();
DROP TABLE financeiro_debitos_privado.operacoes;
DROP TABLE financeiro_debitos_privado.grupos;
DROP TABLE financeiro_debitos_privado.config;
DROP SCHEMA financeiro_debitos_privado;
ALTER TABLE public.debitos_diretos_lancamentos DROP CONSTRAINT ddl_parent_empresa;
DROP INDEX public.dd_id_empresa_unique;
ALTER TABLE public.debitos_diretos_lancamentos DROP COLUMN empresa_id;
ALTER TABLE public.debitos_diretos DROP COLUMN empresa_id;
DO $acl$ DECLARE item record; n text; source aclitem[]; BEGIN
 FOREACH n IN ARRAY ARRAY['debitos_diretos','debitos_diretos_lancamentos'] LOOP
  REVOKE ALL ON public.debitos_diretos FROM PUBLIC,anon,authenticated,service_role;
  IF n='debitos_diretos_lancamentos' THEN REVOKE ALL ON public.debitos_diretos_lancamentos FROM PUBLIC,anon,authenticated,service_role; END IF;
  SELECT CASE WHEN n='debitos_diretos' THEN acl_debitos ELSE acl_lancamentos END INTO source FROM primeline_debitos_20261011.controlo;
  FOR item IN SELECT * FROM aclexplode(source) WHERE grantee<>'postgres'::regrole LOOP
   EXECUTE format('GRANT %s ON public.%I TO %s%s',item.privilege_type,n,CASE WHEN item.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(item.grantee)) END,CASE WHEN item.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
END $acl$;
UPDATE primeline_debitos_20261011.controlo SET state='rolled_back' WHERE singleton;
SELECT 'FINANCEIRO_DEBITOS_ROLLBACK_OK' resultado;
COMMIT;
"""
# Keep original private backup and audit records. Never restore/delete unrelated operational tables.
rollback=rollback.replace("  REVOKE ALL ON public.debitos_diretos FROM PUBLIC,anon,authenticated,service_role;", "  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role',n);")
put('_rollback',rollback)
