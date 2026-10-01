-- Fase B: executar só após deploy e validação dos clientes novos.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF nullif(current_setting('primeline.quadro.frontend_validado',true),'') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: falta identificação do frontend publicado e validado.'; END IF;
 IF to_regclass('primeline_backup.quadro_fase_b_funcoes_20261001') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: executar backup da Fase B.'; END IF;
END $$;
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
