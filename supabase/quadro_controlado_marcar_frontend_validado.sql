-- EXECUÇÃO SEPARADA E MANUAL, apenas APÓS prova operacional em produção.
-- Não executar automaticamente na instalação A/B. Não prova Cloudflare pela BD.
-- Preencher frontend_git_sha opcional com o SHA servido; nunca usar como autorização.
BEGIN;
SET LOCAL lock_timeout='10s';
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN SHARE MODE;
LOCK TABLE primeline_quadro_rollout.controlo,primeline_quadro_rollout.validacoes IN EXCLUSIVE MODE;
SELECT primeline_quadro_rollout.exigir_fase_a();
DO $$
DECLARE
 v_contract_version integer := 1;
 v_frontend_release_id text := 'quadro_frontend_contract_v1';
 v_frontend_git_sha text := NULL; -- opcional: 40 caracteres hexadecimais do SHA publicado.
 c primeline_quadro_rollout.controlo;
BEGIN
 SELECT * INTO STRICT c FROM primeline_quadro_rollout.controlo WHERE singleton;
 IF v_contract_version<>c.contract_version OR v_frontend_release_id<>c.frontend_release_id THEN RAISE EXCEPTION 'FRONTEND_VALIDATION_INVALID: contrato/release errado'; END IF;
 INSERT INTO primeline_quadro_rollout.validacoes(instalacao_id,tentativa,contract_version,frontend_release_id,frontend_git_sha,frontend_validado_por,identidade_a)
 VALUES(c.instalacao_id,c.tentativa,v_contract_version,v_frontend_release_id,v_frontend_git_sha,current_user,c.identidade_a);
END $$;
COMMIT;
