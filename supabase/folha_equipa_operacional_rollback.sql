BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias) OR EXISTS(SELECT 1 FROM folha_privado.equipa_revisoes)
 OR EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE funcao IS NOT NULL)
 OR EXISTS(SELECT 1 FROM public.colaboradores WHERE delegacao IS NOT NULL) OR EXISTS(SELECT 1 FROM public.obras WHERE delegacao IS NOT NULL)
 OR EXISTS(SELECT 1 FROM public.utilizadores WHERE delegacao IS NOT NULL) THEN RAISE EXCEPTION 'ROLLBACK_DATA_PRESENT: preservar dados e preparar forward fix'; END IF;
END $$;
DROP TRIGGER trg_01_equipa_alocacao ON public.quadro_pessoal_alocacao;
DROP FUNCTION public.fn_equipa_operar_v2(text,jsonb,boolean,text);
DROP FUNCTION public.fn_folha_ferias_mapa_v2(date,date);
DO $$ DECLARE f record; BEGIN FOR f IN SELECT * FROM primeline_equipa_backup.funcoes LOOP EXECUTE f.definicao; END LOOP; END $$;
DROP FUNCTION folha_privado.quadro_diario_preservado(text,jsonb,boolean,text);
DROP FUNCTION folha_privado.quadro_contexto_preservado(date,date);
DROP FUNCTION folha_privado.gestao_contexto_preservado(uuid,uuid,date);
DROP TRIGGER equipa_integridade ON public.quadro_equipa_permanencias;
DROP FUNCTION folha_privado.guardar_permanencia();
DROP FUNCTION folha_privado.proteger_alocacao_persistente();
DROP FUNCTION folha_privado.elegivel_equipa(uuid,date);
DROP TABLE folha_privado.equipa_revisoes;
DROP TABLE public.quadro_equipa_permanencias;
ALTER TABLE public.colaboradores DROP COLUMN delegacao;
ALTER TABLE public.obras DROP COLUMN delegacao;
ALTER TABLE public.utilizadores DROP COLUMN delegacao;
ALTER TABLE public.folha_externos_dias DROP COLUMN funcao;
-- Private backup retained. No CASCADE, no operational data deletion.
COMMIT;
