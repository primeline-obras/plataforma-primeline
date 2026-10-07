CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_imovel(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_path text; begin if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.imoveis_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $function$;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_imovel(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_imovel(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_pedido_orcamento(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_path text; begin if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.pedidos_orcamento_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $function$;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_imovel_empresa(p_imovel_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar imóveis.';
  end if;

  if not exists (
    select 1
    from public.imoveis_empresa
    where id = p_imovel_id
  ) then
    raise exception 'Imóvel não encontrado.';
  end if;

  delete from public.imoveis_reunioes_condominio
  where imovel_id = p_imovel_id;

  delete from public.imoveis_empresa
  where id = p_imovel_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_apagar_imovel_empresa(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_imovel_empresa(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_reuniao_condominio(p_reuniao_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar reuniões de condomínio.';
  end if;

  if not exists (
    select 1
    from public.imoveis_reunioes_condominio
    where id = p_reuniao_id
  ) then
    raise exception 'Reunião não encontrada.';
  end if;

  delete from public.imoveis_reunioes_condominio
  where id = p_reuniao_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_apagar_reuniao_condominio(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_reuniao_condominio(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_versao_pedido_orcamento(p_versao_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar versões de pedidos de orçamento.';
  end if;

  if not exists (
    select 1
    from public.pedidos_orcamento_versoes
    where id = p_versao_id
  ) then
    raise exception 'Versão não encontrada.';
  end if;

  delete from public.pedidos_orcamento_versoes
  where id = p_versao_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_apagar_versao_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_versao_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_cancelar_pedido_orcamento(p_pedido_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode cancelar pedidos de orçamento.';
  end if;

  if not exists (
    select 1
    from public.pedidos_orcamento
    where id = p_pedido_id
  ) then
    raise exception 'Pedido de orçamento não encontrado.';
  end if;

  update public.pedidos_orcamento
  set
    estado = 'cancelado',
    situacao_atual = coalesce(
      nullif(btrim(situacao_atual), ''),
      'Cancelado pelo utilizador'
    )
  where id = p_pedido_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_cancelar_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_cancelar_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_gerir_registo_frota(p_tabela text, p_registo_id uuid, p_acao text, p_dados jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row jsonb;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Operação reservada a Administrativo/Gerência.' using errcode='42501'; end if;
  if p_acao not in ('editar','apagar') then raise exception 'Ação inválida.'; end if;
  if p_tabela='viaturas_eventos' then
    if p_acao='editar' then update public.viaturas_eventos set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row;
    else delete from public.viaturas_eventos where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row; end if;
  elsif p_tabela='viaturas_sinistros' then
    if p_acao='editar' then update public.viaturas_sinistros set descricao=coalesce(nullif(btrim(p_dados->>'descricao'),''),descricao),estado=case when p_dados ? 'estado' and p_dados->>'estado' in ('aberto','em_seguradora','fechado') then p_dados->>'estado' else estado end where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row;
    else delete from public.viaturas_sinistros where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row; end if;
  elsif p_tabela='multas' then
    if p_acao='editar' then update public.multas set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(multas) into v_row;
    else delete from public.multas where id=p_registo_id returning to_jsonb(multas) into v_row; end if;
  elsif p_tabela='viaturas_sinistros_anexos' and p_acao='apagar' then delete from public.viaturas_sinistros_anexos where id=p_registo_id returning to_jsonb(viaturas_sinistros_anexos) into v_row;
  elsif p_tabela='multas_anexos' and p_acao='apagar' then delete from public.multas_anexos where id=p_registo_id returning to_jsonb(multas_anexos) into v_row;
  else raise exception 'Tabela de frota não autorizada.'; end if;
  if v_row is null then raise exception 'Registo não encontrado.'; end if;
  return v_row;
end; $function$;
REVOKE ALL ON FUNCTION public.fn_gerir_registo_frota(text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_gerir_registo_frota(text,uuid,text,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_alterar_responsavel_viatura(p_version integer, p_viatura_id uuid, p_novo_colaborador_id uuid, p_revisao_esperada integer, p_request_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v public.viaturas%ROWTYPE;
  c public.colaboradores%ROWTYPE;
  h public.viaturas_atribuicoes_historico%ROWTYPE;
  v_user uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_contexto text;
  v_idempotent boolean := false;
BEGIN
  IF p_version IS DISTINCT FROM 1 OR p_viatura_id IS NULL
     OR p_request_id IS NULL OR p_revisao_esperada IS NULL OR p_revisao_esperada < 0 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: versão ou parâmetros inválidos.' USING ERRCODE = '22023';
  END IF;
  v_user := public.fn_utilizador_atual_id();
  IF v_user IS NULL OR NOT (public.fn_e_admin() OR public.fn_e_administrativo()) THEN
    RAISE EXCEPTION 'FORBIDDEN: operação reservada a Administrativo/Gerência.' USING ERRCODE = '42501';
  END IF;

  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'STALE_REVISION: repita a atribuição em READ COMMITTED.' USING ERRCODE = '40001';
  END IF;

  -- Serializa o mesmo pedido, incluindo tentativas sobre viaturas diferentes.
  -- Colisões do hash apenas serializam pedidos distintos; UNIQUE é a garantia final.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text, 0));
  SELECT * INTO v FROM public.viaturas WHERE id = p_viatura_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: viatura não encontrada.' USING ERRCODE = '22023';
  END IF;

  -- Replay antes do teste de revisão: devolve o resultado original, mesmo após outras trocas.
  SELECT * INTO h FROM public.viaturas_atribuicoes_historico WHERE request_id = p_request_id;
  IF FOUND THEN
    IF h.viatura_id IS DISTINCT FROM p_viatura_id
       OR h.colaborador_novo_id IS DISTINCT FROM p_novo_colaborador_id
       OR h.revisao_anterior IS DISTINCT FROM p_revisao_esperada
       OR h.motivo IS DISTINCT FROM v_motivo
       OR h.alterado_por IS DISTINCT FROM v_user THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: request_id reutilizado com outro pedido ou autor.' USING ERRCODE = '22023';
    END IF;
    v_idempotent := true;
  ELSE
    IF v.atribuicao_revisao IS DISTINCT FROM p_revisao_esperada THEN
      RAISE EXCEPTION 'STALE_REVISION: atribuição alterada; atualize antes de repetir.' USING ERRCODE = '40001';
    END IF;
    IF p_novo_colaborador_id IS NOT NULL THEN
      -- Impede saída/mudança de empresa concorrente durante a validação e gravação.
      SELECT * INTO c FROM public.colaboradores WHERE id = p_novo_colaborador_id FOR SHARE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'VALIDATION_FAILED: colaborador não encontrado.' USING ERRCODE = '22023';
      END IF;
      IF c.empresa_id IS DISTINCT FROM v.empresa_id OR c.data_saida IS NOT NULL THEN
        RAISE EXCEPTION 'VALIDATION_FAILED: colaborador deve estar ativo e pertencer à empresa da viatura.' USING ERRCODE = '22023';
      END IF;
    END IF;
    IF v.colaborador_atribuido_id IS NOT DISTINCT FROM p_novo_colaborador_id THEN
      RAISE EXCEPTION 'VALIDATION_FAILED: responsável já corresponde ao pedido.' USING ERRCODE = '22023';
    END IF;
    IF v.atribuicao_revisao = 2147483647 THEN
      RAISE EXCEPTION 'VALIDATION_FAILED: limite da revisão atingido.' USING ERRCODE = '22023';
    END IF;

    v_contexto := coalesce(current_setting('primeline.atribuicao_viatura_rpc', true), '');
    PERFORM set_config('primeline.atribuicao_viatura_rpc', 'on', true);
    UPDATE public.viaturas
      SET colaborador_atribuido_id = p_novo_colaborador_id,
          atribuicao_revisao = atribuicao_revisao + 1
      WHERE id = v.id;
    -- O trigger existente trata os alertas pendentes. Não duplicar essa lógica.
    INSERT INTO public.viaturas_atribuicoes_historico (
      viatura_id, colaborador_anterior_id, colaborador_novo_id,
      revisao_anterior, revisao_nova, alterado_por, request_id, motivo
    ) VALUES (
      v.id, v.colaborador_atribuido_id, p_novo_colaborador_id,
      v.atribuicao_revisao, v.atribuicao_revisao + 1, v_user, p_request_id, v_motivo
    ) RETURNING * INTO h;
    PERFORM set_config('primeline.atribuicao_viatura_rpc', v_contexto, true);
  END IF;

  RETURN jsonb_build_object(
    'version', 1, 'committed', true, 'idempotent', v_idempotent,
    'viatura_id', h.viatura_id,
    'colaborador_anterior_id', h.colaborador_anterior_id,
    'colaborador_novo_id', h.colaborador_novo_id,
    'atribuicao_revisao', h.revisao_nova, 'historico_id', h.id
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_guardar_validade_viatura(p_version integer, p_viatura_id uuid, p_tipo text, p_operacao text, p_data_atual_esperada date, p_data_base date, p_validade_opcao text, p_nova_data date, p_motivo text, p_request_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v public.viaturas%rowtype;
  e public.viaturas_eventos%rowtype;

  v_user uuid;

  v_data_atual date;
  v_data_nova date;

  v_ciclo_antigo uuid;
  v_ciclo_novo uuid;

  v_tipo_alerta text;
  v_operacao_hist text;
  v_descricao text;

  v_alerta jsonb;
BEGIN

  -- ----------------------------------------------------------
  -- Validação
  -- ----------------------------------------------------------

  IF p_version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: versão inválida.';
  END IF;

  IF p_viatura_id IS NULL
     OR p_tipo NOT IN ('seguro', 'inspecao')
     OR p_operacao NOT IN ('renovar', 'editar_data')
     OR nullif(btrim(p_request_id), '') IS NULL
  THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: dados incompletos.';
  END IF;

  IF NOT (
    public.fn_e_admin()
    OR public.fn_e_administrativo()
  ) THEN
    RAISE EXCEPTION
      'FORBIDDEN: operação reservada a Administrativo/Gerência.'
      USING ERRCODE = '42501';
  END IF;

  v_user := public.fn_utilizador_atual_id();

  IF v_user IS NULL THEN
    RAISE EXCEPTION
      'FORBIDDEN: utilizador não identificado.'
      USING ERRCODE = '42501';
  END IF;

  v_operacao_hist :=
    CASE
      WHEN p_operacao = 'renovar'
        THEN 'renovacao'
      ELSE 'correcao_data'
    END;


  -- ----------------------------------------------------------
  -- Idempotência
  -- ----------------------------------------------------------

  SELECT *
  INTO e
  FROM public.viaturas_eventos
  WHERE request_id = p_request_id;

  IF FOUND THEN

    IF e.viatura_id IS DISTINCT FROM p_viatura_id
       OR e.tipo IS DISTINCT FROM p_tipo
       OR e.validade_operacao IS DISTINCT FROM v_operacao_hist
       OR e.validade_anterior IS DISTINCT FROM p_data_atual_esperada
    THEN
      RAISE EXCEPTION
        'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
    END IF;

    IF p_operacao = 'editar_data' THEN
      IF e.validade_nova IS DISTINCT FROM p_nova_data
         OR coalesce(e.motivo, '') IS DISTINCT FROM
            coalesce(nullif(btrim(p_motivo), ''), '')
      THEN
        RAISE EXCEPTION
          'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
      END IF;
    ELSE
      IF e.validade_base IS DISTINCT FROM p_data_base
         OR e.validade_opcao IS DISTINCT FROM p_validade_opcao
      THEN
        RAISE EXCEPTION
          'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
      END IF;
    END IF;

    SELECT *
    INTO v
    FROM public.viaturas
    WHERE id = p_viatura_id;

    RETURN jsonb_build_object(
      'version', 1,
      'committed', true,
      'idempotent', true,
      'vehicle', to_jsonb(v),
      'event', to_jsonb(e)
    );
  END IF;


  -- ----------------------------------------------------------
  -- Lock da viatura
  -- ----------------------------------------------------------

  SELECT *
  INTO v
  FROM public.viaturas
  WHERE id = p_viatura_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: viatura não encontrada.';
  END IF;


  IF p_tipo = 'seguro' THEN
    v_data_atual := v.seguro_data;
    v_ciclo_antigo := v.seguro_ciclo_id;
    v_tipo_alerta := 'seguro_viatura';
  ELSE
    v_data_atual := v.data_inspecao_proxima;
    v_ciclo_antigo := v.inspecao_ciclo_id;
    v_tipo_alerta := 'inspecao_viatura';
  END IF;


  -- ----------------------------------------------------------
  -- Concorrência otimista
  -- ----------------------------------------------------------

  IF v_data_atual IS DISTINCT FROM p_data_atual_esperada THEN
    RAISE EXCEPTION
      'STALE_REVISION: a validade foi alterada. Atualize antes de repetir.';
  END IF;


  -- ==========================================================
  -- RENOVAR
  -- ==========================================================

  IF p_operacao = 'renovar' THEN

    IF p_data_base IS NULL
       OR p_validade_opcao NOT IN (
         '1_ano',
         '2_anos',
         'outra'
       )
    THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: data de renovação e validade são obrigatórias.';
    END IF;

    IF p_validade_opcao = '1_ano' THEN
      v_data_nova :=
        (p_data_base + interval '1 year')::date;

    ELSIF p_validade_opcao = '2_anos' THEN
      v_data_nova :=
        (p_data_base + interval '2 years')::date;

    ELSE
      IF p_nova_data IS NULL THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: informe o novo vencimento.';
      END IF;

      v_data_nova := p_nova_data;
    END IF;

    IF v_data_nova < p_data_base THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: vencimento anterior à data da renovação.';
    END IF;

    v_descricao :=
      CASE
        WHEN p_tipo = 'seguro'
          THEN 'Renovação do seguro'
        ELSE 'Renovação da inspeção'
      END;


  -- ==========================================================
  -- EDITAR DATA
  -- ==========================================================

  ELSE

    IF p_nova_data IS NULL
       OR nullif(btrim(p_motivo), '') IS NULL
    THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: nova data e motivo são obrigatórios.';
    END IF;

    v_data_nova := p_nova_data;

    v_descricao :=
      CASE
        WHEN p_tipo = 'seguro'
          THEN 'Correção da data do seguro'
        ELSE 'Correção da data da inspeção'
      END;

  END IF;


  IF v_data_nova IS NOT DISTINCT FROM v_data_atual THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: a nova data é igual à atual.';
  END IF;


  -- ----------------------------------------------------------
  -- Resolver alerta antigo
  -- ----------------------------------------------------------

  UPDATE public.alertas
  SET
    estado = 'resolvido',
    resolvido_por = v_user,
    resolvido_em = now()
  WHERE entidade_tipo = 'viaturas'
    AND entidade_id = p_viatura_id
    AND tipo = v_tipo_alerta
    AND estado = 'pendente'
    AND data_evento_referencia
        IS NOT DISTINCT FROM v_data_atual
    AND (
      ocorrencia_chave IS NOT DISTINCT FROM v_ciclo_antigo
      OR ocorrencia_chave IS NULL
    );


  -- ----------------------------------------------------------
  -- Novo ciclo
  -- ----------------------------------------------------------

  v_ciclo_novo := gen_random_uuid();


  -- ----------------------------------------------------------
  -- Atualizar validade
  -- ----------------------------------------------------------

  IF p_tipo = 'seguro' THEN

    UPDATE public.viaturas
    SET
      seguro_data = v_data_nova,
      seguro_ciclo_id = v_ciclo_novo
    WHERE id = p_viatura_id
    RETURNING *
    INTO v;

  ELSE

    UPDATE public.viaturas
    SET
      data_inspecao_proxima = v_data_nova,
      inspecao_ciclo_id = v_ciclo_novo
    WHERE id = p_viatura_id
    RETURNING *
    INTO v;

  END IF;


  -- ----------------------------------------------------------
  -- Criar histórico protegido
  -- ----------------------------------------------------------

  PERFORM set_config(
    'primeline.validade_viatura_rpc',
    'on',
    true
  );

  INSERT INTO public.viaturas_eventos (
    viatura_id,
    tipo,
    data,
    descricao,
    validade_operacao,
    validade_anterior,
    validade_nova,
    validade_base,
    validade_opcao,
    motivo,
    registado_por,
    request_id
  )
  VALUES (
    p_viatura_id,
    p_tipo,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_data_base
      ELSE current_date
    END,

    v_descricao,
    v_operacao_hist,
    v_data_atual,
    v_data_nova,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_data_base
      ELSE NULL
    END,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_validade_opcao
      ELSE NULL
    END,

    nullif(btrim(p_motivo), ''),
    v_user,
    p_request_id
  )
  RETURNING *
  INTO e;


  -- ----------------------------------------------------------
  -- Se já estiver dentro de 15 dias cria o alerta agora.
  -- Caso contrário, fica para o job diário.
  -- ----------------------------------------------------------

  v_alerta :=
    public.fn_criar_alerta_validade_viatura(
      p_viatura_id,
      p_tipo
    );


  RETURN jsonb_build_object(
    'version', 1,
    'committed', true,
    'idempotent', false,

    'validity',
      jsonb_build_object(
        'type', p_tipo,
        'operation', p_operacao,
        'previous_date', v_data_atual,
        'new_date', v_data_nova,
        'cycle_id', v_ciclo_novo
      ),

    'vehicle', to_jsonb(v),
    'event', to_jsonb(e),
    'alert', v_alerta
  );

END;
$function$;
REVOKE ALL ON FUNCTION public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_rnc(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_path text; v_obra uuid;
begin
  select a.arquivo_url,r.obra_id into v_path,v_obra from public.rnc_anexos a join public.rnc r on r.id=a.rnc_id where a.id=p_anexo_id;
  if not found then raise exception 'Anexo não encontrado.'; end if;
  if not public.fn_pode_editar_obra(v_obra) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.rnc_anexos where id=p_anexo_id; return v_path;
end; $function$;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_rnc(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_rnc(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_documento_obra(p_documento_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_obra_id uuid;
begin
  select obra_id
  into v_obra_id
  from public.documentos_obra
  where id = p_documento_id;

  if v_obra_id is null then
    raise exception 'Documento não encontrado.';
  end if;

  if not public.fn_pode_editar_documentos_obra(v_obra_id) then
    raise exception 'Sem permissão para apagar este documento.';
  end if;

  delete from public.documentos_obra
  where id = p_documento_id;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_apagar_documento_obra(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_documento_obra(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_registar_documento_obra(p_obra_id uuid, p_tipo text, p_nome_arquivo text, p_arquivo_url text)
 RETURNS documentos_obra
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_documento public.documentos_obra;
  v_utilizador_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão autenticada obrigatória.';
  end if;

  if not public.fn_pode_editar_obra(p_obra_id) then
    raise exception 'Sem permissão para enviar documentos para esta obra.';
  end if;

  if p_tipo is null or p_tipo not in (
    'contrato',
    'orcamento',
    'plantas_projeto',
    'licencas',
    'planeamento_detalhado',
    'outro'
  ) then
    raise exception 'Tipo de documento inválido.';
  end if;

  if nullif(btrim(p_nome_arquivo), '') is null then
    raise exception 'O nome do ficheiro é obrigatório.';
  end if;

  if nullif(btrim(p_arquivo_url), '') is null
     or p_arquivo_url not like p_obra_id::text || '/%' then
    raise exception 'O caminho do documento não pertence à obra indicada.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();
  if v_utilizador_id is null then
    raise exception 'O utilizador autenticado não está associado a public.utilizadores.';
  end if;

  insert into public.documentos_obra (
    obra_id,
    tipo,
    nome_arquivo,
    arquivo_url,
    enviado_por
  )
  values (
    p_obra_id,
    p_tipo,
    btrim(p_nome_arquivo),
    p_arquivo_url,
    v_utilizador_id
  )
  returning * into v_documento;

  return v_documento;
end;
$function$;
REVOKE ALL ON FUNCTION public.fn_registar_documento_obra(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_registar_documento_obra(uuid,text,text,text) TO authenticated;
