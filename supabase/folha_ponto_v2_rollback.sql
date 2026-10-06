BEGIN;
-- Fail closed if new facts/history exist. Preserve production evidence.
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF to_regclass('folha_privado.legacy_cutover') IS NOT NULL THEN RAISE EXCEPTION 'ROLLBACK_CUTOVER_ACTIVE: verify dedicated rollback first'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_historico) OR EXISTS(SELECT 1 FROM public.folha_registos)
 OR EXISTS(SELECT 1 FROM public.folha_externos) OR EXISTS(SELECT 1 FROM public.folha_externos_dias)
 OR EXISTS(SELECT 1 FROM public.folha_he) OR EXISTS(SELECT 1 FROM public.folha_config_empresa)
 OR EXISTS(SELECT 1 FROM public.folha_horarios) OR EXISTS(SELECT 1 FROM folha_privado.operacoes)
 THEN RAISE EXCEPTION 'ROLLBACK_DATA_PRESENT: preservar factos e configuração; requer plano específico'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.fn_quadro_aplicar_interno(p_colaborador_id uuid,p_data date,
 p_antes jsonb,p_depois jsonb,p_origem text,p_request_id uuid DEFAULT NULL,p_simular boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; q public.quadro_pessoal_alocacao;
 v_antes jsonb; v_revisao integer; v_row jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO c FROM public.colaboradores WHERE id=p_colaborador_id AND empresa_id=u.empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador de outra empresa ou inexistente.' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR p_origem NOT IN('quadro','cadastro_rh','importacao_rh') THEN RAISE EXCEPTION 'VALIDATION_ERROR: data/origem inválida.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_colaborador_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(p_colaborador_id::text||':'||p_data::text,0));
 v_antes:=public.fn_quadro_dia_explicito(p_colaborador_id,p_data);
 IF v_antes IS DISTINCT FROM p_antes THEN RAISE EXCEPTION 'STALE_REVISION: alocação alterada; recarregue.'; END IF;
 IF jsonb_typeof(p_depois) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'VALIDATION_ERROR: alocações inválidas.'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) a GROUP BY a->>'id' HAVING count(*)>1)
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: IDs repetidos.'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) a JOIN jsonb_array_elements(p_depois) b
 ON a->>'id'<b->>'id' WHERE a->>'periodo'='dia_inteiro' OR b->>'periodo'='dia_inteiro' OR a->>'periodo'=b->>'periodo')
 THEN RAISE EXCEPTION 'OVERLAP_CONFLICT: destinos simultâneos; legado requer revisão humana.'; END IF;
 -- Permissão em TODAS as origens e destinos; responsabilidade não é presença.
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_antes||p_depois) LOOP
  IF NOT (public.fn_quadro_pode_gerir_v1(NULL) OR (p_origem IN('cadastro_rh','importacao_rh') AND public.fn_rh_empresa(false)=u.empresa_id)) AND
    (v_row->>'tipo_alocacao'<>'obra' OR NOT public.fn_quadro_minha_obra_v1((v_row->>'obra_id')::uuid))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: origem/destino fora da equipa autorizada.' USING ERRCODE='42501'; END IF;
 END LOOP;
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_depois) LOOP
  q:=jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,v_row);
  IF q.id IS NULL OR q.colaborador_id IS DISTINCT FROM p_colaborador_id OR q.data IS DISTINCT FROM p_data
   OR q.periodo IS NULL OR q.periodo NOT IN('manha','tarde','dia_inteiro')
   OR q.tipo_alocacao IS NULL OR q.tipo_alocacao NOT IN('obra','escritorio','garantia','pontual')
   OR (q.tipo_alocacao='obra' AND (q.obra_id IS NULL OR q.descricao_livre IS NOT NULL))
   OR (q.tipo_alocacao<>'obra' AND (q.obra_id IS NOT NULL OR nullif(btrim(q.descricao_livre),'') IS NULL))
  THEN RAISE EXCEPTION 'VALIDATION_ERROR: destino/período inválido.'; END IF;
  IF q.obra_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=q.obra_id AND o.empresa_id=u.empresa_id)
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: obra de outra empresa.' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao x WHERE x.id=q.id AND (x.colaborador_id<>p_colaborador_id OR x.data<>p_data))
  THEN RAISE EXCEPTION 'VALIDATION_ERROR: identidade de outra alocação.'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_antes) b WHERE b=v_row) THEN
   IF c.data_admissao>p_data OR (c.data_saida IS NOT NULL AND c.data_saida<=p_data)
   THEN RAISE EXCEPTION 'VALIDATION_ERROR: colaborador indisponível nesta data.'; END IF;
   -- Mantém a proteção instalada: qualquer ausência registada bloqueia a nova alocação.
   IF EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p_colaborador_id AND a.data=p_data)
   THEN RAISE EXCEPTION 'ABSENCE_CONFLICT: colaborador de férias/ausente nesta data.'; END IF;
  END IF;
 END LOOP;
 IF p_simular THEN RETURN jsonb_build_object('allocations',p_depois,'changed',p_antes IS DISTINCT FROM p_depois); END IF;
 IF p_antes=p_depois THEN RETURN jsonb_build_object('allocations',p_antes,'changed',false); END IF;
 INSERT INTO public.quadro_escrita_interna VALUES(txid_current(),p_colaborador_id,p_data,u.id,p_origem,p_request_id);
 DELETE FROM public.quadro_pessoal_alocacao x WHERE x.colaborador_id=p_colaborador_id AND x.data=p_data
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) d WHERE (d->>'id')::uuid=x.id);
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_depois) LOOP
  q:=jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,v_row);
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao x WHERE x.id=q.id) THEN
   UPDATE public.quadro_pessoal_alocacao x SET obra_id=q.obra_id,periodo=q.periodo,
     tipo_alocacao=q.tipo_alocacao,descricao_livre=q.descricao_livre
   WHERE x.id=q.id AND (x.obra_id,x.periodo,x.tipo_alocacao,x.descricao_livre)
     IS DISTINCT FROM (q.obra_id,q.periodo,q.tipo_alocacao,q.descricao_livre);
  ELSE
   INSERT INTO public.quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,periodo,semana_inicio,tipo_alocacao,descricao_livre,criado_por)
   VALUES(q.id,p_colaborador_id,q.obra_id,p_data,q.periodo,date_trunc('week',p_data::timestamp)::date,q.tipo_alocacao,q.descricao_livre,u.id);
  END IF;
 END LOOP;
 -- Um alerta por par origem/destino e destinatário, incluindo split/merge dos períodos.
 FOR v_row IN SELECT jsonb_build_object('origem',b->>'obra_id','destino',a->>'obra_id','id',min(a->>'id'))
 FROM jsonb_array_elements(p_depois) a LEFT JOIN jsonb_array_elements(p_antes) b
 ON b->>'periodo'='dia_inteiro' OR a->>'periodo'='dia_inteiro' OR b->>'periodo'=a->>'periodo'
 WHERE (b->>'obra_id') IS DISTINCT FROM (a->>'obra_id')
 GROUP BY b->>'obra_id',a->>'obra_id' LOOP
  PERFORM public.fn_quadro_notificar_controlado_v1(p_colaborador_id,p_data,(v_row->>'origem')::uuid,(v_row->>'destino')::uuid,(v_row->>'id')::uuid);
 END LOOP;
 DELETE FROM public.quadro_escrita_interna WHERE transacao=txid_current() AND colaborador_id=p_colaborador_id AND data=p_data;
 INSERT INTO public.quadro_dias_revisoes(colaborador_id,data,revisao,obras_visiveis)
 VALUES(p_colaborador_id,p_data,1,ARRAY(SELECT DISTINCT (r->>'obra_id')::uuid FROM jsonb_array_elements(p_antes||p_depois) r WHERE r->>'obra_id' IS NOT NULL))
 ON CONFLICT(colaborador_id,data) DO UPDATE SET revisao=quadro_dias_revisoes.revisao+1,
 obras_visiveis=ARRAY(SELECT DISTINCT x FROM unnest(quadro_dias_revisoes.obras_visiveis||EXCLUDED.obras_visiveis) x)
 RETURNING revisao INTO v_revisao;
 RETURN jsonb_build_object('allocations',public.fn_quadro_dia_explicito(p_colaborador_id,p_data),'revision',v_revisao,'changed',true);
END $$;
DROP TRIGGER trg_00_folha_absencias_lock ON public.ausencias;
DROP TRIGGER trg_00_folha_alocacao_lock ON public.quadro_pessoal_alocacao;
DROP TRIGGER trg_folha_ausencia_reconciliar ON public.ausencias;
DROP TRIGGER trg_folha_alocacao_reconciliar ON public.quadro_pessoal_alocacao;
DROP FUNCTION folha_privado.reconciliar_dependencia();
DROP FUNCTION folha_privado.reconciliar_dia(uuid,date,uuid,text);
DROP FUNCTION folha_privado.reconciliar_he(public.folha_registos);
DROP FUNCTION folha_privado.estado_efetivo(integer,boolean,integer,boolean,boolean);
DROP TRIGGER trg_00_folha_ponto_lock ON public.ponto_pessoal_obra;
DROP TRIGGER trg_00_folha_he_lock ON public.horas_extraordinarias;
DROP TRIGGER folha_he_origin_conflict ON public.horas_extraordinarias;
DROP FUNCTION folha_privado.proteger_he_legado();
DROP TRIGGER folha_legacy_conflict ON public.ponto_pessoal_obra;
DROP FUNCTION public.fn_folha_operar_v2(text,jsonb,boolean,text);
DROP FUNCTION public.fn_folha_historico_v2(jsonb);
DROP FUNCTION public.fn_folha_pessoas_v2(date,uuid);
DROP FUNCTION public.fn_folha_contexto_v2(date,uuid);
DROP FUNCTION folha_privado.alocar(text,jsonb,uuid,date,uuid,boolean);
DROP FUNCTION folha_privado.save(jsonb,uuid,date,uuid,boolean);
DROP FUNCTION folha_privado.normal(uuid,uuid,date);
DROP FUNCTION folha_privado.linha(uuid,uuid,date,text);
DROP FUNCTION folha_privado.quadro_autorizado(uuid,date,jsonb,jsonb);
DROP FUNCTION folha_privado.obra(uuid,boolean);
DROP FUNCTION folha_privado.local(uuid,uuid,boolean);
DROP FUNCTION folha_privado.admin();
DROP FUNCTION folha_privado.superuser();
DROP FUNCTION folha_privado.adm_operacional();
DROP FUNCTION folha_privado.ator();
DROP FUNCTION folha_privado.facts(jsonb,date);
DROP FUNCTION folha_privado.lock_dia(uuid,date);
DROP FUNCTION folha_privado.lock_legado();
DROP FUNCTION folha_privado.proteger_legado();
DROP TABLE public.folha_he;
DROP TABLE public.folha_historico;
DROP TABLE public.folha_registos;
DROP FUNCTION folha_privado.invalidar_review_especial();
DROP TABLE public.folha_externos_dias;
DROP TABLE public.folha_externos;
DROP TABLE public.folha_horarios;
DROP TABLE public.folha_config_empresa;
DROP TABLE folha_privado.operacoes;

DROP FUNCTION folha_privado.integridade();
DROP FUNCTION folha_privado.imutavel();
DROP SCHEMA folha_privado;
COMMIT;
