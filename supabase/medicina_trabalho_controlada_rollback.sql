-- Rollback sem perda: recusado depois de qualquer operação real.
BEGIN;
SET LOCAL lock_timeout = '10s';
LOCK TABLE public.colaboradores,public.medicina_trabalho,public.alertas,
 public.medicina_operacoes,public.medicina_alertas_historico,
 public.medicina_instalacao_snapshot IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.medicina_trabalho WHERE registado_por IS NOT NULL
 OR request_id IS NOT NULL OR revisao<>0 OR anulado_em IS NOT NULL OR anulado_por IS NOT NULL) THEN
  RAISE EXCEPTION 'ROLLBACK_REFUSED: existem metadados novos; não perder autoria/revisão.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.medicina_operacoes) OR EXISTS(SELECT 1 FROM public.medicina_alertas_historico) THEN
  RAISE EXCEPTION 'ROLLBACK_REFUSED: existem operações; preservar histórico e preparar rollback específico.';
 END IF;
 IF (SELECT jsonb_agg(to_jsonb(m)-ARRAY['registado_por','request_id','revisao','anulado_em','anulado_por'] ORDER BY id)
 FROM public.medicina_trabalho m) IS DISTINCT FROM (SELECT linhas FROM public.medicina_instalacao_snapshot) THEN
  RAISE EXCEPTION 'ROLLBACK_REFUSED: dados antigos divergentes.';
 END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM public.alertas a
 WHERE tipo IN ('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento'))
 IS DISTINCT FROM (SELECT alertas FROM public.medicina_instalacao_snapshot) THEN
  RAISE EXCEPTION 'ROLLBACK_REFUSED: alertas divergentes; não apagar histórico.';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.fn_verificar_primeiras_consultas_medicina()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inseridos integer := 0;
begin
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    c.empresa_id,
    'primeira_consulta_medicina',
    'colaboradores',
    c.id,
    'Marcar primeira consulta: ' || c.nome,
    'O colaborador completou 30 dias desde a admissão sem registo em Medicina do Trabalho.',
    c.data_admissao + 30,
    0,
    c.data_admissao + 30,
    'administrativo',
    'pendente'
  from public.colaboradores c
  where c.data_saida is null
    and c.data_admissao is not null
    and c.data_admissao + 30 <= current_date
    and not exists (
      select 1
      from public.medicina_trabalho m
      where m.colaborador_id = c.id
    )
  on conflict do nothing;

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_verificar_alertas_vencimento()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inseridos integer := 0;
  v_parcial integer := 0;

  v_doc_colaborador integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_documento_colaborador',
      30
    )::integer;

  v_epi integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_epi',
      30
    )::integer;

  v_medicina integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_medicina',
      30
    )::integer;

  v_inspecao integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_viatura_inspecao',
      15
    )::integer;

  v_documentos_empresa integer[] :=
    public.fn_parametro_operacional_dias(
      'antecedencias_alerta_documento_empresa',
      array[15,7,3]
    );
begin
  -- Documentos dos colaboradores.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento a vencer: '
      || coalesce(c.nome, d.nome_arquivo, 'colaborador'),
    coalesce(d.tipo_documento, 'Documento')
      || ' · validade em '
      || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    v_doc_colaborador,
    d.data_validade - v_doc_colaborador,
    'administrativo',
    'pendente'
  from public.documentos d
  left join public.colaboradores c
    on c.id = d.entidade_id
  where d.entidade_tipo = 'colaborador'
    and d.data_validade is not null
    and d.data_validade - v_doc_colaborador <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Documentos da empresa.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento da empresa a vencer',
    coalesce(d.tipo_documento, d.nome_arquivo, 'Documento')
      || ' · validade em '
      || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    limiar.dias,
    d.data_validade - limiar.dias,
    'administrativo',
    'pendente'
  from public.documentos d
  cross join lateral (
    select min(dias) as dias
    from unnest(v_documentos_empresa) as valores(dias)
    where d.data_validade - current_date <= dias
  ) limiar
  where d.entidade_tipo = 'empresa'
    and d.data_validade is not null
    and limiar.dias is not null
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- EPI.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    c.empresa_id,
    'validade_epi',
    'epis',
    e.id,
    'EPI a vencer: ' || c.nome,
    coalesce(
      to_jsonb(e)->>'tipo_epi',
      to_jsonb(e)->>'tipo_equipamento',
      to_jsonb(e)->>'tipo',
      'EPI'
    )
      || ' · validade em '
      || to_char(e.data_validade, 'DD/MM/YYYY'),
    e.data_validade,
    v_epi,
    e.data_validade - v_epi,
    'administrativo',
    'pendente'
  from public.epis e
  join public.colaboradores c
    on c.id = e.colaborador_id
  where c.data_saida is null
    and e.data_validade is not null
    and e.data_validade - v_epi <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Medicina do trabalho.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    c.empresa_id,
    'consulta_medicina',
    'medicina_trabalho',
    m.id,
    'Consulta de medicina a vencer: ' || c.nome,
    'Próxima consulta em '
      || to_char(m.data_proxima_consulta, 'DD/MM/YYYY'),
    m.data_proxima_consulta,
    v_medicina,
    m.data_proxima_consulta - v_medicina,
    'administrativo',
    'pendente'
  from public.medicina_trabalho m
  join public.colaboradores c
    on c.id = m.colaborador_id
  where c.data_saida is null
    and m.data_proxima_consulta is not null
    and m.data_proxima_consulta - v_medicina <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Inspeções das viaturas.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    v.empresa_id,
    'inspecao_viatura',
    'viaturas',
    v.id,
    'Inspeção da viatura a vencer',
    concat_ws(
      ' · ',
      nullif(v.marca_modelo, ''),
      nullif(v.matricula, ''),
      'inspeção em '
        || to_char(v.data_inspecao_proxima, 'DD/MM/YYYY')
    ),
    v.data_inspecao_proxima,
    v_inspecao,
    v.data_inspecao_proxima - v_inspecao,
    'administrativo',
    'pendente'
  from public.viaturas v
  where v.data_inspecao_proxima is not null
    and v.data_inspecao_proxima - v_inspecao <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  return v_inseridos;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_atualizar_colaborador_ciclo_vida(p_colaborador_id uuid, p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date DEFAULT NULL::date, p_data_saida date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_colaborador public.colaboradores%rowtype;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A gestão de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_data_saida is not null
     and p_data_saida < p_data_admissao then
    raise exception
      'A data de saída não pode ser anterior à data de admissão.';
  end if;

  update public.colaboradores
  set
    nome = btrim(p_nome),
    funcao = btrim(p_funcao),
    data_admissao = p_data_admissao,
    data_nascimento = p_data_nascimento,
    data_saida = p_data_saida
  where id = p_colaborador_id
  returning * into v_colaborador;

  if v_colaborador.id is null then
    raise exception 'Colaborador não encontrado.';
  end if;

  if p_data_saida is not null then
    delete from public.alertas a
    where a.estado = 'pendente'
      and (
        (
          a.tipo = 'primeira_consulta_medicina'
          and a.entidade_tipo = 'colaboradores'
          and a.entidade_id = p_colaborador_id
        )
        or (
          a.entidade_tipo = 'epis'
          and a.entidade_id in (
            select e.id
            from public.epis e
            where e.colaborador_id = p_colaborador_id
          )
        )
        or (
          a.entidade_tipo = 'medicina_trabalho'
          and a.entidade_id in (
            select m.id
            from public.medicina_trabalho m
            where m.colaborador_id = p_colaborador_id
          )
        )
      );
  elsif to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    perform public.fn_verificar_alertas_vencimento();
  end if;

  return to_jsonb(v_colaborador);
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_atualizar_colaborador_ciclo_vida(p_colaborador_id uuid, p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_data_saida date, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_colaborador public.colaboradores%rowtype;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A gestão de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_data_saida is not null
     and p_data_saida < p_data_admissao then
    raise exception
      'A data de saída não pode ser anterior à data de admissão.';
  end if;

  if p_valor_hora is not null and p_valor_hora < 0 then
    raise exception 'O valor/hora não pode ser negativo.';
  end if;

  update public.colaboradores
  set
    nome = btrim(p_nome),
    funcao = btrim(p_funcao),
    nivel = nullif(btrim(p_nivel), ''),
    valor_hora = p_valor_hora,
    nif = nullif(btrim(p_nif), ''),
    email = nullif(btrim(p_email), ''),
    contacto = nullif(btrim(p_contacto), ''),
    morada = nullif(btrim(p_morada), ''),
    data_admissao = p_data_admissao,
    data_nascimento = p_data_nascimento,
    data_saida = p_data_saida
  where id = p_colaborador_id
  returning *
  into v_colaborador;

  if v_colaborador.id is null then
    raise exception 'Colaborador não encontrado.';
  end if;

  if p_data_saida is not null then
    delete from public.alertas a
    where a.estado = 'pendente'
      and (
        (
          a.tipo = 'primeira_consulta_medicina'
          and a.entidade_tipo = 'colaboradores'
          and a.entidade_id = p_colaborador_id
        )
        or (
          a.entidade_tipo = 'epis'
          and a.entidade_id in (
            select e.id
            from public.epis e
            where e.colaborador_id = p_colaborador_id
          )
        )
        or (
          a.entidade_tipo = 'medicina_trabalho'
          and a.entidade_id in (
            select m.id
            from public.medicina_trabalho m
            where m.colaborador_id = p_colaborador_id
          )
        )
      );
  elsif to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    perform public.fn_verificar_alertas_vencimento();
  end if;

  return to_jsonb(v_colaborador);
end;
$function$;

DROP TRIGGER trg_medicina_admissao_historico ON public.medicina_trabalho;
DROP TRIGGER trg_medicina_proteger ON public.medicina_trabalho;
DROP POLICY medicina_leitura ON public.medicina_trabalho;
DROP TABLE public.medicina_alertas_historico;
DROP TABLE public.medicina_operacoes;
DROP FUNCTION public.fn_medicina_registar_consulta(integer,uuid,date,text,date,uuid);
DROP FUNCTION public.fn_medicina_corrigir_consulta(integer,uuid,date,text,date,integer,uuid,text);
DROP FUNCTION public.fn_medicina_anular_consulta(integer,uuid,integer,uuid,text);
DROP FUNCTION public.fn_medicina_consultar_colaborador(integer,uuid);
DROP FUNCTION public.fn_medicina_guardar_interno(integer,text,uuid,uuid,date,text,date,integer,uuid,text);
DROP FUNCTION public.fn_medicina_admissao_historico();
DROP FUNCTION public.fn_medicina_reconciliar_alertas(uuid);
DROP FUNCTION public.fn_medicina_atual(uuid);
DROP FUNCTION public.fn_medicina_pode_gerir(uuid);
DROP FUNCTION public.fn_medicina_proteger();
DROP FUNCTION public.fn_medicina_proteger_historico();
ALTER TABLE public.medicina_trabalho DROP CONSTRAINT medicina_datas_coerentes,
 DROP CONSTRAINT medicina_anulacao_coerente,
 DROP COLUMN registado_por,DROP COLUMN request_id,DROP COLUMN revisao,
 DROP COLUMN anulado_em,DROP COLUMN anulado_por;
-- O índice parcial depende de anulado_em e é removido ao eliminar essa coluna.
DO $$
DECLARE p jsonb; v_roles text;
BEGIN
 FOR p IN SELECT value FROM public.medicina_instalacao_snapshot,
  LATERAL jsonb_array_elements(policies_originais)
 LOOP
  SELECT string_agg(quote_ident(value),',') INTO v_roles FROM jsonb_array_elements_text(p->'roles');
  EXECUTE format('CREATE POLICY %I ON public.medicina_trabalho AS %s FOR %s TO %s%s%s',
   p->>'policyname',p->>'permissive',p->>'cmd',v_roles,
   CASE WHEN p->>'qual' IS NULL THEN '' ELSE ' USING ('||(p->>'qual')||')' END,
   CASE WHEN p->>'with_check' IS NULL THEN '' ELSE ' WITH CHECK ('||(p->>'with_check')||')' END);
 END LOOP;
END $$;
REVOKE SELECT(id,colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta,criado_em)
 ON public.medicina_trabalho FROM authenticated;
-- Restaurar todos os grants originais, incluindo service_role, sem os presumir.
DO $$
DECLARE g jsonb; r text;
BEGIN
 FOR r IN SELECT DISTINCT value->>'role' FROM public.medicina_instalacao_snapshot,
  LATERAL jsonb_array_elements(grants_originais)
 LOOP
  EXECUTE format('REVOKE ALL ON public.medicina_trabalho FROM %s',
    CASE WHEN r='PUBLIC' THEN 'PUBLIC' ELSE quote_ident(r) END);
 END LOOP;
 FOR g IN SELECT value FROM public.medicina_instalacao_snapshot,
  LATERAL jsonb_array_elements(grants_originais)
 LOOP
  EXECUTE format('GRANT %s ON public.medicina_trabalho TO %s%s',g->>'privilege',
    CASE WHEN g->>'role'='PUBLIC' THEN 'PUBLIC' ELSE quote_ident(g->>'role') END,
    CASE WHEN (g->>'grantable')::boolean THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
END $$;
DROP TABLE public.medicina_instalacao_snapshot;
COMMIT;
