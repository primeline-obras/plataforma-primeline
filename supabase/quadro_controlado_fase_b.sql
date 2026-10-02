-- Fase B: executar só após deploy e validação dos clientes novos.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
DO $$ BEGIN
 IF to_regclass('primeline_quadro_rollout.controlo') IS NULL OR to_regclass('primeline_quadro_rollout.validacoes') IS NULL THEN RAISE EXCEPTION 'FRONTEND_VALIDATION_REQUIRED: controlo privado ausente'; END IF;
 PERFORM primeline_quadro_rollout.exigir_fase_a();
 PERFORM primeline_quadro_rollout.exigir_validacao();
 IF to_regclass('primeline_backup.quadro_fase_b_estrutura_20261001') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: executar backup B com referência estrutural validada A'; END IF;
 IF to_regclass('primeline_backup.quadro_fase_b_funcoes_20261001') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: executar backup da Fase B.'; END IF;
 IF to_regclass('primeline_backup.quadro_fase_b_controlo_20261001') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: backup sem identidade privada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_backup.quadro_fase_b_controlo_20261001 b JOIN primeline_quadro_rollout.controlo c ON c.instalacao_id=b.instalacao_id AND c.identidade_a=b.identidade_a WHERE c.singleton AND b.singleton AND b.estado='a') THEN RAISE EXCEPTION 'PRECONDITION_FAILED: backup pertence a outra instalação/estrutura A'; END IF;

END $$;
-- Postcheck A: somente leitura, aborta em divergência.
DO $$ DECLARE r record; role_name text; f record; t text; priv text; BEGIN
 FOR t IN SELECT unnest(ARRAY['quadro_dias_revisoes','quadro_operacoes','quadro_escrita_interna']) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=to_regclass('public.'||t) AND c.relrowsecurity AND pg_get_userbyid(c.relowner)='postgres') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: tabela privada/RLS/owner %',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: policy em tabela privada %',t; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(role_name,'public.'||t,priv) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: acesso privado %, %, %',role_name,t,priv; END IF;
   END LOOP;
   FOR r IN SELECT attname FROM pg_attribute WHERE attrelid=to_regclass('public.'||t) AND attnum>0 AND NOT attisdropped LOOP
    IF has_column_privilege(role_name,'public.'||t,r.attname,'SELECT') OR has_column_privilege(role_name,'public.'||t,r.attname,'INSERT') OR has_column_privilege(role_name,'public.'||t,r.attname,'UPDATE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: grant de coluna privada %',t; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
 FOR f IN SELECT p.*,p.oid::regprocedure::text signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND (p.proname LIKE 'fn_quadro_%v1' OR p.proname IN('fn_quadro_aplicar_interno','fn_quadro_renomear_interno','fn_quadro_resolver_data','fn_quadro_dia_explicito','fn_quadro_ler_obra','fn_quadro_criar_colaborador_interno')) LOOP
  IF NOT f.prosecdef OR pg_get_userbyid(f.proowner)<>'postgres' OR NOT coalesce(f.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp'] THEN RAISE EXCEPTION 'POSTCHECK_FAILED: owner/security/search_path %',f.signature; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(role_name,f.oid,'EXECUTE') IS DISTINCT FROM (role_name='authenticated' AND (f.proname IN('fn_quadro_operar_v1','fn_quadro_contexto_v1') )) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: EXECUTE %, %',role_name,f.signature; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: PUBLIC execute %',f.signature; END IF;
 END LOOP;
 FOR f IN SELECT * FROM primeline_backup.quadro_funcoes_20261001 WHERE assinatura LIKE 'fn_criar_colaborador_com_alocacao(%' OR assinatura LIKE 'fn_rh_guardar_interno(%' OR assinatura='fn_registar_movimento_quadro()' OR assinatura='fn_quadro_proteger_escrita()' OR assinatura='fn_quadro_notificar_movimentacao_encarregado()' OR assinatura LIKE 'fn_quadro_operar(%' LOOP
  IF (SELECT p.proacl::text FROM pg_proc p WHERE p.oid=f.assinatura::regprocedure) IS DISTINCT FROM f.acl OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid=f.assinatura::regprocedure) IS DISTINCT FROM f.owner THEN RAISE EXCEPTION 'POSTCHECK_FAILED: ACL/owner legado modificado %',f.assinatura; END IF;
 END LOOP;
 FOR f IN SELECT * FROM primeline_backup.quadro_funcoes_20261001 WHERE assinatura LIKE 'fn_listar_ponto_obra(%' OR assinatura LIKE 'fn_guardar_ponto_obra(%' OR assinatura LIKE 'fn_pode_gerir_quadro(%' OR assinatura LIKE 'fn_quadro_minha_obra(%' OR assinatura='fn_pode_consultar_quadro()' LOOP
  IF replace(pg_get_functiondef(f.assinatura::regprocedure),chr(13),'') IS DISTINCT FROM replace(f.definicao,chr(13),'') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: consumidor legado alterado %',f.assinatura; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT tgisinternal AND tgenabled<>'O') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: trigger desativado'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p') AND p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?quadro_pessoal_alocacao\M' AND p.proname NOT IN('fn_quadro_aplicar_interno','fn_quadro_operar')) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: writer não inventariado'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM pg_policies x WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos')) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM primeline_backup.quadro_policies_20261001 x) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: policy legado alterado na Fase A'; END IF;
 FOR r IN SELECT * FROM primeline_backup.quadro_tabelas_20261001 WHERE tabela IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos','public.quadro_pessoal_alocacao','public.quadro_pessoal_movimentos') LOOP
  IF (SELECT relacl::text FROM pg_class WHERE oid=r.tabela::regclass) IS DISTINCT FROM r.relacl::text THEN RAISE EXCEPTION 'POSTCHECK_FAILED: ACL legado alterado %',r.tabela; END IF;
 END LOOP;
 FOR r IN SELECT c.oid FROM pg_class c JOIN pg_depend d ON d.objid=c.oid WHERE c.relkind='S' AND d.refobjid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass) LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_sequence_privilege(role_name,r.oid,'USAGE') OR has_sequence_privilege(role_name,r.oid,'UPDATE') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: grant de sequência'; END IF;
  END LOOP;
 END LOOP;
END $$;
-- UUIDs usam gen_random_uuid(): não são introduzidas sequências novas.
SELECT 'POSTCHECK_A_OK' status;
-- Controlo de rollout não é RPC pública; owner/ACL/RLS privados obrigatórios.
SELECT primeline_quadro_rollout.exigir_privacidade();
SELECT primeline_quadro_rollout.exigir_fase_a();
-- Consumo atómico: uma validação autoriza apenas esta tentativa.
UPDATE primeline_quadro_rollout.validacoes SET consumida_em=clock_timestamp()
WHERE id=primeline_quadro_rollout.exigir_validacao();
UPDATE primeline_quadro_rollout.controlo SET estado='b',fase_b_aplicada_em=clock_timestamp() WHERE singleton;
CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.quadro_pessoal_alocacao;
BEGIN
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id,NEW.colaborador_id,NEW.data) IS DISTINCT FROM (OLD.id,OLD.colaborador_id,OLD.data)
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: identidade imutável.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current()
 AND p.colaborador_id=q.colaborador_id AND p.data=q.data AND p.utilizador_id=public.fn_utilizador_atual_id())
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: use a operação controlada de alocação.' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 RAISE EXCEPTION 'CLIENT_UPGRADE_REQUIRED: recarregue o Quadro antes de editar.' USING ERRCODE='42501'; END $$;
-- Escritores adaptados acima; só agora fechar DML direto da aplicação.
DO $$ DECLARE r record; BEGIN FOR r IN SELECT policyname,tablename FROM pg_policies
 WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP
 EXECUTE format('DROP POLICY %I ON public.%I',r.policyname,r.tablename);
 END LOOP; END $$;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public.quadro_pessoal_alocacao FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
DO $$ DECLARE c record; BEGIN FOR c IN SELECT attrelid::regclass tabela,attname FROM pg_attribute WHERE attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND attnum>0 AND NOT attisdropped LOOP
 EXECUTE format('REVOKE ALL (%I) ON TABLE %s FROM PUBLIC,anon,authenticated,service_role',c.attname,c.tabela);
 END LOOP; END $$;
GRANT SELECT ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos TO authenticated;
CREATE POLICY quadro_controlado_leitura ON public.quadro_pessoal_alocacao FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE c.id=colaborador_id AND u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND (EXISTS(SELECT 1 FROM public.utilizadores g WHERE g.id=public.fn_utilizador_atual_id() AND g.ativo IS TRUE AND g.funcao IN('administrativo','gestao_plataforma','gerencia')) OR (tipo_alocacao='obra' AND public.fn_quadro_ler_obra(obra_id)))));
CREATE POLICY quadro_controlado_historico ON public.quadro_pessoal_movimentos FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND u.empresa_id=quadro_pessoal_movimentos.empresa_id)
 AND (EXISTS(SELECT 1 FROM public.utilizadores g WHERE g.id=public.fn_utilizador_atual_id() AND g.ativo IS TRUE AND g.funcao IN('administrativo','gestao_plataforma','gerencia')) OR public.fn_quadro_ler_obra(obra_origem_id) OR public.fn_quadro_ler_obra(obra_destino_id)));
REVOKE ALL ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_quadro_ler_obra(uuid) TO authenticated;
COMMIT;
