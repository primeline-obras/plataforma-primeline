-- Primeline | Ciclo de vida dos colaboradores e alocação inicial
-- Executar no SQL Editor antes de usar o novo formulário da Equipa.

do $$
declare
  r record;
begin
  -- Substitui apenas checks que regulam tipo_alocacao; preserva os restantes.
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.quadro_pessoal_alocacao'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%tipo_alocacao%'
  loop
    execute format('alter table public.quadro_pessoal_alocacao drop constraint %I', r.conname);
  end loop;
end;
$$;

alter table public.quadro_pessoal_alocacao
  add constraint quadro_pessoal_alocacao_tipo_check
  check (tipo_alocacao in ('obra', 'escritorio', 'garantia', 'pontual'));

create or replace function public.fn_criar_colaborador_com_alocacao(
  p_nome text,
  p_funcao text,
  p_data_admissao date,
  p_data_nascimento date default null,
  p_alocacao_tipo text default 'obra',
  p_obra_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa_id uuid;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_colaborador public.colaboradores%rowtype;
  v_alocacao public.quadro_pessoal_alocacao%rowtype;
  v_semana_inicio date;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'A criação de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null or nullif(btrim(p_funcao), '') is null or p_data_admissao is null then
    raise exception 'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_alocacao_tipo not in ('obra', 'escritorio') then
    raise exception 'A alocação inicial deve ser uma obra ativa ou o Escritório.';
  end if;

  select u.empresa_id into v_empresa_id
  from public.utilizadores u
  where u.id = v_utilizador_id;

  if v_empresa_id is null and public.fn_e_admin() then
    select e.id into v_empresa_id from public.empresas e limit 1;
  end if;

  if v_empresa_id is null then
    raise exception 'Não foi possível identificar a empresa do utilizador atual.';
  end if;

  if p_alocacao_tipo = 'obra' then
    if p_obra_id is null or not exists (
      select 1 from public.obras o
      where o.id = p_obra_id
        and coalesce(lower(o.situacao), '') not in ('concluida', 'concluído', 'concluido', 'cancelada')
    ) then
      raise exception 'Selecione uma obra ativa válida para a alocação inicial.';
    end if;
  elsif p_obra_id is not null then
    raise exception 'A alocação de Escritório não pode ficar ligada a uma obra.';
  end if;

  insert into public.colaboradores (
    empresa_id, nome, funcao, data_admissao, data_nascimento, data_saida
  ) values (
    v_empresa_id, btrim(p_nome), btrim(p_funcao), p_data_admissao, p_data_nascimento, null
  ) returning * into v_colaborador;

  v_semana_inicio := p_data_admissao - (extract(isodow from p_data_admissao)::integer - 1);

  insert into public.quadro_pessoal_alocacao (
    colaborador_id, obra_id, tipo_alocacao, descricao_livre,
    semana_inicio, data, periodo, criado_por
  ) values (
    v_colaborador.id,
    case when p_alocacao_tipo = 'obra' then p_obra_id else null end,
    p_alocacao_tipo,
    case when p_alocacao_tipo = 'escritorio' then 'Escritório' else null end,
    v_semana_inicio,
    p_data_admissao,
    'dia_inteiro',
    v_utilizador_id
  ) returning * into v_alocacao;

  return jsonb_build_object(
    'colaborador', to_jsonb(v_colaborador),
    'alocacao', to_jsonb(v_alocacao)
  );
end;
$$;

create or replace function public.fn_atualizar_colaborador_ciclo_vida(
  p_colaborador_id uuid,
  p_nome text,
  p_funcao text,
  p_data_admissao date,
  p_data_nascimento date default null,
  p_data_saida date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_colaborador public.colaboradores%rowtype;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'A gestão de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null or nullif(btrim(p_funcao), '') is null or p_data_admissao is null then
    raise exception 'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_data_saida is not null and p_data_saida < p_data_admissao then
    raise exception 'A data de saída não pode ser anterior à data de admissão.';
  end if;

  update public.colaboradores
  set nome = btrim(p_nome),
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
    -- Retira apenas alertas automáticos ainda pendentes. Horas, ausências,
    -- documentos, medicina, EPI e alocações históricas permanecem intactos.
    delete from public.alertas a
    where a.estado = 'pendente'
      and (
        (a.tipo = 'primeira_consulta_medicina' and a.entidade_tipo = 'colaboradores' and a.entidade_id = p_colaborador_id)
        or (a.entidade_tipo = 'epis' and a.entidade_id in (select e.id from public.epis e where e.colaborador_id = p_colaborador_id))
        or (a.entidade_tipo = 'medicina_trabalho' and a.entidade_id in (select m.id from public.medicina_trabalho m where m.colaborador_id = p_colaborador_id))
      );
  elsif to_regprocedure('public.fn_verificar_alertas_vencimento()') is not null then
    -- Recria imediatamente alertas aplicáveis depois de uma reativação.
    perform public.fn_verificar_alertas_vencimento();
  end if;

  return to_jsonb(v_colaborador);
end;
$$;

revoke all on function public.fn_criar_colaborador_com_alocacao(text, text, date, date, text, uuid) from public;
revoke all on function public.fn_atualizar_colaborador_ciclo_vida(uuid, text, text, date, date, date) from public;
grant execute on function public.fn_criar_colaborador_com_alocacao(text, text, date, date, text, uuid) to authenticated;
grant execute on function public.fn_atualizar_colaborador_ciclo_vida(uuid, text, text, date, date, date) to authenticated;

select
  to_regprocedure('public.fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid)') is not null as criar_colaborador,
  to_regprocedure('public.fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date)') is not null as gerir_ciclo_vida,
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.quadro_pessoal_alocacao'::regclass
      and conname = 'quadro_pessoal_alocacao_tipo_check'
  ) as escritorio_no_quadro;
