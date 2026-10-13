-- Local readers only. They confer nothing, generate no payment and do not invent expected hours.
CREATE FUNCTION public.fn_folha_relatorio_horas_v3(p_obra_id uuid,p_inicio date,p_fim date,p_kind text DEFAULT NULL,p_fornecedor_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $report$
DECLARE u public.utilizadores;records jsonb;legacy jsonb;days jsonb;weeks jsonb;months jsonb;
BEGIN
 u:=folha_privado.ator();IF p_obra_id IS NULL OR p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>30 OR p_kind IS NOT NULL AND p_kind NOT IN('primeline','external') THEN RAISE EXCEPTION 'REPORT_RANGE_INVALID: até 31 dias';END IF;
 PERFORM folha_privado.obra(p_obra_id);
 IF p_fornecedor_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.fornecedores WHERE id=p_fornecedor_id AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'work_id',f.obra_id,'person_id',coalesce(f.colaborador_id,f.externo_id),'kind',CASE WHEN f.externo_id IS NULL THEN 'primeline' ELSE 'external' END,'name',coalesce(c.nome,e.nome),'provider_id',e.fornecedor_id,'provider_name',provider.nome,'intervals',f.intervals,'minutes',f.minutes,'open',f.estado='open','corrected',EXISTS(SELECT 1 FROM public.folha_historico h WHERE h.empresa_id=u.empresa_id AND h.person_id=coalesce(f.colaborador_id,f.externo_id) AND h.kind=CASE WHEN f.externo_id IS NULL THEN 'primeline' ELSE 'external' END AND h.obra_id=f.obra_id AND h.data=f.data AND h.antes IS NOT NULL AND h.antes<>'null'::jsonb),'last_changed_at',f.atualizado_em,'changed_by',f.atualizado_por) ORDER BY f.data,f.id),'[]') INTO records
 FROM public.folha_registos f LEFT JOIN public.colaboradores c ON c.id=f.colaborador_id AND c.empresa_id=u.empresa_id LEFT JOIN public.folha_externos e ON e.id=f.externo_id AND e.empresa_id=u.empresa_id LEFT JOIN public.fornecedores provider ON provider.id=e.fornecedor_id AND provider.empresa_id=u.empresa_id
 WHERE f.empresa_id=u.empresa_id AND f.obra_id=p_obra_id AND f.data BETWEEN p_inicio AND p_fim AND (p_kind IS NULL OR p_kind='primeline' AND f.colaborador_id IS NOT NULL OR p_kind='external' AND f.externo_id IS NOT NULL) AND (p_fornecedor_id IS NULL OR e.fornecedor_id=p_fornecedor_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('source','legacy','original',to_jsonb(p)) ORDER BY p.data,p.id),'[]') INTO legacy FROM public.ponto_pessoal_obra p WHERE p.empresa_id=u.empresa_id AND p.obra_id=p_obra_id AND p.data BETWEEN p_inicio AND p_fim AND p_kind IS DISTINCT FROM 'external' AND p_fornecedor_id IS NULL;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.date,x.person_id),'[]') INTO days FROM (SELECT r->>'person_id' person_id,r->>'kind' kind,r->>'date' date,sum((r->>'minutes')::integer)::integer minutes FROM jsonb_array_elements(records) r GROUP BY r->>'person_id',r->>'kind',r->>'date') x;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.week,x.person_id),'[]') INTO weeks FROM (SELECT r->>'person_id' person_id,r->>'kind' kind,date_trunc('week',(r->>'date')::date)::date week,sum((r->>'minutes')::integer)::integer minutes FROM jsonb_array_elements(records) r GROUP BY r->>'person_id',r->>'kind',date_trunc('week',(r->>'date')::date)::date) x;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.month_start,x.person_id),'[]') INTO months FROM (SELECT r->>'person_id' person_id,r->>'kind' kind,date_trunc('month',(r->>'date')::date)::date month_start,sum((r->>'minutes')::integer)::integer minutes FROM jsonb_array_elements(records) r GROUP BY r->>'person_id',r->>'kind',date_trunc('month',(r->>'date')::date)::date) x;
 RETURN jsonb_build_object('version',3,'committed',false,'work_id',p_obra_id,'from',p_inicio,'to',p_fim,'records',records,'daily',days,'weekly',weeks,'monthly',months,'legacy',legacy,'legacy_included_in_totals',false,'financial_effect',false,'classification_included',false);
END $report$;
CREATE FUNCTION public.fn_folha_conferencia_contexto_v3(p_colaborador_id uuid,p_competencia date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $monthly$
DECLARE u public.utilizadores;facts jsonb;records jsonb;evals jsonb;
BEGIN
 u:=folha_privado.ator();IF NOT folha_privado.admin() OR NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p_colaborador_id AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: conferência interna' USING ERRCODE='42501';END IF;
 IF p_competencia IS NULL OR extract(day FROM p_competencia)<>1 THEN RAISE EXCEPTION 'MONTH_REQUIRED';END IF;
 facts:=folha_privado.payroll_facts(p_colaborador_id,p_competencia);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'work_id',f.obra_id,'intervals',f.intervals,'minutes',f.minutes,'state',f.estado,'changed_by',f.atualizado_por,'changed_at',f.atualizado_em) ORDER BY f.data,f.id),'[]') INTO records FROM public.folha_registos f WHERE f.empresa_id=u.empresa_id AND f.colaborador_id=p_colaborador_id AND f.data>=p_competencia AND f.data<(p_competencia+interval '1 month')::date;
 SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.data,a.id),'[]') INTO evals FROM public.folha_avaliacoes_diarias a WHERE a.empresa_id=u.empresa_id AND a.colaborador_id=p_colaborador_id AND a.data>=p_competencia AND a.data<(p_competencia+interval '1 month')::date;
 RETURN jsonb_build_object('version',3,'committed',false,'person_id',p_colaborador_id,'month',p_competencia,'records',records,'evaluations',evals,'facts',facts,'he_policy','HR-27','financial_effect',false,'conference_write_capability',false,'expected_monthly_minutes',NULL,'expected_coverage_state','requires_daily_reference_coverage');
END $monthly$;
CREATE FUNCTION public.fn_folha_horas_contexto_v3(p_data date,p_obra_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $context$
DECLARE u public.utilizadores;c jsonb;row_data jsonb;rows jsonb:='[]';j public.folha_jornadas_individuais_versoes;cut date;
BEGIN
 u:=folha_privado.ator();c:=public.fn_folha_contexto_v2(p_data,p_obra_id);SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 FOR row_data IN SELECT value FROM jsonb_array_elements(c->'rows') LOOP
  j:=NULL;IF cut IS NOT NULL AND p_data>=cut THEN SELECT * INTO j FROM public.folha_jornadas_individuais_versoes WHERE empresa_id=u.empresa_id AND colaborador_id=(row_data->>'person_id')::uuid AND vigente_desde<=p_data AND (vigente_ate IS NULL OR vigente_ate>p_data);END IF;
  rows:=rows||jsonb_build_array(row_data||jsonb_build_object('individual_reference',CASE WHEN j.id IS NULL THEN NULL ELSE jsonb_build_object('confirmed',true,'source','individual','version_id',j.id,'revision',j.revision,'effective_from',j.vigente_desde,'effective_to',j.vigente_ate,'week',j.semana) END));
 END LOOP;
 RETURN c||jsonb_build_object('version',3,'rows',rows,'he_policy','HR-27','reference_edit_capability',false,'operational_write_capabilities',jsonb_build_object('existing_periods_save',true,'neutral_faltou',true,'free_destinations',false,'normal_individual_evaluation',false));
END $context$;
REVOKE ALL ON FUNCTION public.fn_folha_relatorio_horas_v3(uuid,date,date,text,uuid),public.fn_folha_conferencia_contexto_v3(uuid,date),public.fn_folha_horas_contexto_v3(date,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_relatorio_horas_v3(uuid,date,date,text,uuid),public.fn_folha_conferencia_contexto_v3(uuid,date),public.fn_folha_horas_contexto_v3(date,uuid) TO authenticated;