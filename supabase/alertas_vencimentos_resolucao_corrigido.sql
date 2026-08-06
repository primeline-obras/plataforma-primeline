-- PRIMELINE | Bloco 2 corrigido: alertas de vencimento e resolução explícita
--
-- Esta migração instala as funções, mas NÃO executa a geração de alertas e
-- NÃO altera os agendamentos pg_cron. Testar manualmente antes de agendar.

begin;

-- O trigger anterior apagava e recriava alertas pendentes sempre que um
-- documento era alterado. A geração passa a ser exclusivamente diária.
drop trigger if exists trg_alerta_validade_documento on public.documentos;

-- Impede duplicados para a mesma ocorrência e antecedência. A expressão
-- também cobre alertas cuja antecedência seja nula.
create unique index if not exists alertas_ocorrencia_unica_idx
on public.alertas (
  tipo,
  entidade_tipo,
  entidade_id,
  data_evento_referencia,
  coalesce(antecedencia_dias, -1)
);

-- Resolver é uma ação explícita. Abrir o sino ou consultar o alerta não o
-- modifica. A função preserva quem resolveu e quando resolveu.
create or replace function public.fn_resolver_alerta(p_alerta_id uuid)
returns public.alertas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerta public.alertas;
  v_utilizador_id uuid;
begin
  v_utilizador_id := public.fn_utilizador_atual_id();

  if v_utilizador_id is null then
    raise exception 'Sessão autenticada inválida.';
  end if;

  select *
    into v_alerta
  from public.alertas
  where id = p_alerta_id
  for update;

  if not found then
    raise exception 'Alerta não encontrado.';
  end if;

  if not (
    public.fn_e_administrativo()
    or (
      public.fn_e_financeiro()
      and v_alerta.destinatario_role in ('financeiro', 'tesouraria')
    )
    or (
      v_alerta.obra_id is not null
      and public.fn_pode_editar_obra(v_alerta.obra_id)
    )
  ) then
    raise exception 'Sem permissão para resolver este alerta.';
  end if;

  if v_alerta.estado = 'resolvido' then
    return v_alerta;
  end if;

  update public.alertas
  set estado = 'resolvido',
      resolvido_por = v_utilizador_id,
      resolvido_em = now()
  where id = p_alerta_id
  returning * into v_alerta;

  return v_alerta;
end;
$$;

revoke all on function public.fn_resolver_alerta(uuid) from public, anon;
grant execute on function public.fn_resolver_alerta(uuid) to authenticated;

-- A primeira consulta mantém o alerta como histórico. O registo nunca é
-- apagado automaticamente quando a consulta é criada ou o colaborador sai.
create or replace function public.fn_verificar_primeiras_consultas_medicina()
returns integer
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.fn_verificar_primeiras_consultas_medicina() from public, anon, authenticated;

-- Gera apenas alertas cujo prazo de aviso já chegou. Alertas resolvidos não
-- são recriados devido ao índice único por ocorrência/antecedência.
create or replace function public.fn_verificar_alertas_vencimento()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inseridos integer := 0;
  v_parcial integer := 0;
begin
  -- Documentos de colaboradores: 30 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento a vencer: ' || coalesce(c.nome, d.nome_arquivo, 'colaborador'),
    coalesce(d.tipo_documento, 'Documento') || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    30,
    d.data_validade - 30,
    'administrativo',
    'pendente'
  from public.documentos d
  left join public.colaboradores c on c.id = d.entidade_id
  where d.entidade_tipo = 'colaborador'
    and d.data_validade is not null
    and d.data_validade - 30 <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Documentos da empresa: avisos progressivos a 15, 7 e 3 dias. Em cada
  -- execução cria apenas o nível mais urgente já atingido.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento da empresa a vencer',
    coalesce(d.tipo_documento, d.nome_arquivo, 'Documento') || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    prazo.dias,
    d.data_validade - prazo.dias,
    'administrativo',
    'pendente'
  from public.documentos d
  cross join lateral (
    select case
      when d.data_validade - current_date <= 3 then 3
      when d.data_validade - current_date <= 7 then 7
      else 15
    end as dias
  ) prazo
  where d.entidade_tipo = 'empresa'
    and d.data_validade is not null
    and d.data_validade - 15 <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- EPI: 30 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    c.empresa_id,
    'validade_epi',
    'epis',
    e.id,
    'EPI a vencer: ' || c.nome,
    e.tipo_epi || ' · validade em ' || to_char(e.data_validade, 'DD/MM/YYYY'),
    e.data_validade,
    30,
    e.data_validade - 30,
    'administrativo',
    'pendente'
  from public.epis e
  join public.colaboradores c on c.id = e.colaborador_id
  where c.data_saida is null
    and e.data_validade is not null
    and e.data_validade - 30 <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Medicina do trabalho: 30 dias antes da próxima consulta.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    c.empresa_id,
    'consulta_medicina',
    'medicina_trabalho',
    m.id,
    'Consulta de medicina a vencer: ' || c.nome,
    'Próxima consulta em ' || to_char(m.data_proxima_consulta, 'DD/MM/YYYY'),
    m.data_proxima_consulta,
    30,
    m.data_proxima_consulta - 30,
    'administrativo',
    'pendente'
  from public.medicina_trabalho m
  join public.colaboradores c on c.id = m.colaborador_id
  where c.data_saida is null
    and m.data_proxima_consulta is not null
    and m.data_proxima_consulta - 30 <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Inspeção de viaturas: 15 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v.empresa_id,
    'inspecao_viatura',
    'viaturas',
    v.id,
    'Inspeção da viatura a vencer',
    concat_ws(' · ', nullif(v.marca_modelo, ''), nullif(v.matricula, ''),
      'inspeção em ' || to_char(v.data_inspecao_proxima, 'DD/MM/YYYY')),
    v.data_inspecao_proxima,
    15,
    v.data_inspecao_proxima - 15,
    'administrativo',
    'pendente'
  from public.viaturas v
  where v.data_inspecao_proxima is not null
    and v.data_inspecao_proxima - 15 <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  return v_inseridos;
end;
$$;

revoke all on function public.fn_verificar_alertas_vencimento() from public, anon, authenticated;

-- Função pronta para o cron futuro. Ainda não é agendada nesta migração.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_primeiras_consultas integer;
  v_vencimentos integer;
begin
  v_primeiras_consultas := public.fn_verificar_primeiras_consultas_medicina();
  v_vencimentos := public.fn_verificar_alertas_vencimento();

  return jsonb_build_object(
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos
  );
end;
$$;

revoke all on function public.fn_executar_rotinas_diarias() from public, anon, authenticated;

commit;

-- Validação estrutural (não cria alertas):
select
  to_regprocedure('public.fn_resolver_alerta(uuid)') is not null as rpc_resolver,
  to_regprocedure('public.fn_verificar_alertas_vencimento()') is not null as funcao_vencimentos,
  to_regprocedure('public.fn_executar_rotinas_diarias()') is not null as rotina_diaria,
  not exists (
    select 1 from pg_trigger
    where tgname = 'trg_alerta_validade_documento'
      and not tgisinternal
  ) as trigger_antigo_removido,
  to_regclass('public.alertas_ocorrencia_unica_idx') is not null as indice_deduplicacao;
