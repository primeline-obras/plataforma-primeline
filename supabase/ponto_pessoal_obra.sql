-- PRIMELINE GO | Ponto diário do pessoal em obra.
-- O Administrativo aloca no Quadro de Pessoal; o Encarregado regista o ponto
-- apenas das pessoas efetivamente alocadas às suas obras.

begin;

create table if not exists public.ponto_pessoal_obra (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  obra_id uuid not null references public.obras(id) on delete cascade,
  colaborador_id uuid not null references public.colaboradores(id) on delete restrict,
  data date not null,
  periodos_alocados text[] not null default array['manha','tarde']::text[],
  estado text not null check (estado in ('presente','falta_com_justificacao','falta_sem_justificacao')),
  entrada_manha time,
  saida_manha time,
  entrada_tarde time,
  saida_tarde time,
  horas numeric(5,2) not null default 0 check (horas >= 0 and horas <= 24),
  observacao text,
  justificacao_estado text not null default 'nao_aplicavel'
    check (justificacao_estado in ('nao_aplicavel','pendente','validada','rejeitada')),
  registado_por uuid not null references public.utilizadores(id),
  atualizado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (colaborador_id, obra_id, data)
);

create index if not exists ponto_pessoal_obra_data_obra_idx
  on public.ponto_pessoal_obra(data desc, obra_id);
create index if not exists ponto_pessoal_obra_colaborador_idx
  on public.ponto_pessoal_obra(colaborador_id, data desc);

create or replace function public.fn_ponto_horas(
  p_entrada_manha time,
  p_saida_manha time,
  p_entrada_tarde time,
  p_saida_tarde time
)
returns numeric
language sql
immutable
as $function$
  select round((
    coalesce(extract(epoch from (p_saida_manha - p_entrada_manha)), 0)
    + coalesce(extract(epoch from (p_saida_tarde - p_entrada_tarde)), 0)
  )::numeric / 3600, 2);
$function$;

create or replace function public.fn_listar_ponto_obra(
  p_data date default current_date,
  p_obra_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and v_atual.funcao <> 'encarregado' then
    raise exception 'O ponto está disponível apenas para o Administrativo, Gestão e Encarregados.' using errcode = '42501';
  end if;
  if p_obra_id is not null and not exists (
    select 1 from public.obras o where o.id = p_obra_id and o.empresa_id = v_empresa_id
      and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
  ) then raise exception 'Sem permissão para consultar o ponto desta obra.' using errcode = '42501'; end if;

  return jsonb_build_object(
    'data', p_data,
    'pode_validar', v_pode_gerir,
    'obras', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'nome', o.nome) order by o.numero, o.nome)
      from public.obras o
      where o.empresa_id = v_empresa_id
        and o.situacao in ('preparacao','em_curso','receb_provisoria')
        and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
    ), '[]'::jsonb),
    'linhas', case when p_obra_id is null then '[]'::jsonb else coalesce((
      with eventos as (
        select q.*, slot.periodo_efetivo
        from public.quadro_pessoal_alocacao q
        join public.colaboradores c on c.id = q.colaborador_id and c.empresa_id = v_empresa_id
        cross join lateral unnest(case when q.periodo = 'dia_inteiro'
          then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
        where q.data <= p_data and c.data_saida is null
      ), efetivos as (
        select distinct on (colaborador_id, periodo_efetivo)
          colaborador_id, obra_id, tipo_alocacao, periodo_efetivo, data, criado_em
        from eventos
        order by colaborador_id, periodo_efetivo, data desc, criado_em desc, id desc
      ), equipa as (
        select e.colaborador_id, e.obra_id,
          array_agg(e.periodo_efetivo order by e.periodo_efetivo) as periodos
        from efetivos e
        where e.obra_id = p_obra_id and e.tipo_alocacao = 'obra'
        group by e.colaborador_id, e.obra_id
      )
      select jsonb_agg(jsonb_build_object(
        'colaborador_id', c.id,
        'nome', c.nome,
        'funcao', c.funcao,
        'periodos', eq.periodos,
        'ponto', case when p.id is null then null else to_jsonb(p) end,
        'ausencia', case when a.id is null then null else to_jsonb(a) end
      ) order by
        case
          when lower(coalesce(c.funcao,'')) like '%encarreg%' then 1
          when lower(coalesce(c.funcao,'')) like '%pedreiro%' then 2
          when lower(coalesce(c.funcao,'')) like '%servente%' then 3
          else 4 end,
        c.nome)
      from equipa eq
      join public.colaboradores c on c.id = eq.colaborador_id
      left join public.ponto_pessoal_obra p
        on p.colaborador_id = c.id and p.obra_id = p_obra_id and p.data = p_data
      left join public.ausencias a
        on a.colaborador_id = c.id and a.data = p_data
    ), '[]'::jsonb) end
  );
end;
$function$;

create or replace function public.fn_guardar_ponto_obra(
  p_obra_id uuid,
  p_colaborador_id uuid,
  p_data date,
  p_estado text,
  p_entrada_manha time default null,
  p_saida_manha time default null,
  p_entrada_tarde time default null,
  p_saida_tarde time default null,
  p_observacao text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
  v_periodos text[];
  v_horas numeric(5,2);
  v_registo public.ponto_pessoal_obra;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and not public.fn_e_encarregado_da_obra(p_obra_id) then
    raise exception 'Sem permissão para registar o ponto desta obra.' using errcode = '42501';
  end if;
  if p_estado not in ('presente','falta_com_justificacao','falta_sem_justificacao') then
    raise exception 'Estado de presença inválido.';
  end if;
  if p_estado = 'falta_com_justificacao' and nullif(btrim(p_observacao), '') is null then
    raise exception 'Indique a justificação apresentada pelo colaborador.';
  end if;

  with eventos as (
    select q.*, slot.periodo_efetivo
    from public.quadro_pessoal_alocacao q
    cross join lateral unnest(case when q.periodo = 'dia_inteiro'
      then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
    where q.colaborador_id = p_colaborador_id and q.data <= p_data
  ), efetivos as (
    select distinct on (periodo_efetivo) obra_id, tipo_alocacao, periodo_efetivo
    from eventos order by periodo_efetivo, data desc, criado_em desc, id desc
  )
  select array_agg(periodo_efetivo order by periodo_efetivo) into v_periodos
  from efetivos where obra_id = p_obra_id and tipo_alocacao = 'obra';

  if coalesce(cardinality(v_periodos), 0) = 0 then
    raise exception 'Este colaborador não está alocado a esta obra na data indicada.';
  end if;
  if not exists (select 1 from public.colaboradores c where c.id = p_colaborador_id and c.empresa_id = v_empresa_id) then
    raise exception 'Colaborador inexistente ou fora da empresa.';
  end if;
  if p_estado = 'presente' and exists (
    select 1 from public.ausencias a
    where a.colaborador_id = p_colaborador_id and a.data = p_data
      and (a.tipo = 'ferias' or a.estado in ('confirmada','justificada'))
  ) then
    raise exception 'Este colaborador tem uma ausência ou férias já confirmadas nesta data.';
  end if;

  if p_estado = 'presente' then
    if 'manha' = any(v_periodos) and (p_entrada_manha is null or p_saida_manha is null or p_saida_manha <= p_entrada_manha) then
      raise exception 'Preencha um horário válido para a manhã.';
    end if;
    if 'tarde' = any(v_periodos) and (p_entrada_tarde is null or p_saida_tarde is null or p_saida_tarde <= p_entrada_tarde) then
      raise exception 'Preencha um horário válido para a tarde.';
    end if;
    if p_saida_manha is not null and p_entrada_tarde is not null and p_entrada_tarde < p_saida_manha then
      raise exception 'Os períodos da manhã e da tarde não podem sobrepor-se.';
    end if;
    if not ('manha'=any(v_periodos)) then p_entrada_manha:=null; p_saida_manha:=null; end if;
    if not ('tarde'=any(v_periodos)) then p_entrada_tarde:=null; p_saida_tarde:=null; end if;
    v_horas := public.fn_ponto_horas(
      p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde
    );
    if v_horas <= 0 or v_horas > 16 then raise exception 'O total diário deve estar entre 0 e 16 horas.'; end if;
    if exists (
      select 1 from public.ponto_pessoal_obra outro
      where outro.colaborador_id=p_colaborador_id and outro.data=p_data
        and outro.obra_id<>p_obra_id and outro.estado='presente'
        and (
          (p_entrada_manha is not null and outro.entrada_manha is not null and p_entrada_manha < outro.saida_manha and outro.entrada_manha < p_saida_manha)
          or (p_entrada_manha is not null and outro.entrada_tarde is not null and p_entrada_manha < outro.saida_tarde and outro.entrada_tarde < p_saida_manha)
          or (p_entrada_tarde is not null and outro.entrada_manha is not null and p_entrada_tarde < outro.saida_manha and outro.entrada_manha < p_saida_tarde)
          or (p_entrada_tarde is not null and outro.entrada_tarde is not null and p_entrada_tarde < outro.saida_tarde and outro.entrada_tarde < p_saida_tarde)
        )
    ) then raise exception 'O horário sobrepõe-se ao ponto deste colaborador noutra obra.'; end if;
  else
    v_horas := 0;
    p_entrada_manha := null; p_saida_manha := null;
    p_entrada_tarde := null; p_saida_tarde := null;
  end if;

  insert into public.ponto_pessoal_obra(
    empresa_id, obra_id, colaborador_id, data, periodos_alocados, estado,
    entrada_manha, saida_manha, entrada_tarde, saida_tarde, horas,
    observacao, justificacao_estado, registado_por, atualizado_por, atualizado_em
  ) values (
    v_empresa_id, p_obra_id, p_colaborador_id, p_data, v_periodos, p_estado,
    p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde, v_horas,
    nullif(btrim(p_observacao), ''),
    case when p_estado='falta_com_justificacao' then 'pendente' else 'nao_aplicavel' end,
    v_atual.id, v_atual.id, now()
  ) on conflict (colaborador_id, obra_id, data) do update set
    periodos_alocados = excluded.periodos_alocados,
    estado = excluded.estado,
    entrada_manha = excluded.entrada_manha,
    saida_manha = excluded.saida_manha,
    entrada_tarde = excluded.entrada_tarde,
    saida_tarde = excluded.saida_tarde,
    horas = excluded.horas,
    observacao = excluded.observacao,
    justificacao_estado = excluded.justificacao_estado,
    atualizado_por = v_atual.id,
    atualizado_em = now()
  returning * into v_registo;

  return to_jsonb(v_registo);
end;
$function$;

create or replace function public.fn_validar_justificacao_ponto(
  p_ponto_id uuid,
  p_decisao text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_atual public.utilizadores; v_registo public.ponto_pessoal_obra;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'A validação da justificação está reservada ao Administrativo e à Gestão.' using errcode='42501';
  end if;
  if p_decisao not in ('validada','rejeitada') then raise exception 'Decisão inválida.'; end if;
  select * into v_atual from public.utilizadores where id=public.fn_utilizador_atual_id() and ativo is true;
  update public.ponto_pessoal_obra set justificacao_estado=p_decisao,
    atualizado_por=v_atual.id, atualizado_em=now()
  where id=p_ponto_id and empresa_id=v_atual.empresa_id and estado='falta_com_justificacao'
  returning * into v_registo;
  if v_registo.id is null then raise exception 'Registo de ponto inexistente ou sem justificação pendente.'; end if;
  return to_jsonb(v_registo);
end;
$function$;

revoke all on function public.fn_ponto_horas(time,time,time,time) from public, anon;
revoke all on function public.fn_listar_ponto_obra(date,uuid) from public, anon;
revoke all on function public.fn_guardar_ponto_obra(uuid,uuid,date,text,time,time,time,time,text) from public, anon;
revoke all on function public.fn_validar_justificacao_ponto(uuid,text) from public, anon;
grant execute on function public.fn_ponto_horas(time,time,time,time) to authenticated;
grant execute on function public.fn_listar_ponto_obra(date,uuid) to authenticated;
grant execute on function public.fn_guardar_ponto_obra(uuid,uuid,date,text,time,time,time,time,text) to authenticated;
grant execute on function public.fn_validar_justificacao_ponto(uuid,text) to authenticated;

alter table public.ponto_pessoal_obra enable row level security;
revoke all on public.ponto_pessoal_obra from anon, authenticated;

do $audit$
begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_ponto_pessoal_obra on public.ponto_pessoal_obra;
    create trigger trg_auditoria_ponto_pessoal_obra
    after insert or update or delete on public.ponto_pessoal_obra
    for each row execute function public.fn_registar_log_auditoria('id');
  end if;
end;
$audit$;

commit;

select
  to_regclass('public.ponto_pessoal_obra') is not null as ponto_obra_ativo,
  to_regprocedure('public.fn_listar_ponto_obra(date,uuid)') is not null as consulta_ponto_ativa,
  to_regprocedure('public.fn_guardar_ponto_obra(uuid,uuid,date,text,time,time,time,time,text)') is not null as registo_ponto_ativo,
  to_regprocedure('public.fn_validar_justificacao_ponto(uuid,text)') is not null as validacao_justificacao_ativa;
