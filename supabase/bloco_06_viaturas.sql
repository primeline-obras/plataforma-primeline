-- PRIMELINE | Bloco 6 - gestão de viaturas, sinistros, multas e seguro.
-- Executar uma vez no SQL Editor do Supabase com uma conta owner.

begin;

create table if not exists public.viaturas_eventos (
  id uuid primary key default gen_random_uuid(),
  viatura_id uuid not null references public.viaturas(id),
  tipo text not null check (tipo = any (array[
    'revisao'::text, 'inspecao'::text, 'pneus'::text,
    'bateria'::text, 'reparacao'::text, 'outro'::text
  ])),
  data date not null,
  descricao text,
  custo numeric,
  fornecedor_id uuid references public.fornecedores(id),
  criado_em timestamptz not null default now()
);

create table if not exists public.viaturas_sinistros (
  id uuid primary key default gen_random_uuid(),
  viatura_id uuid not null references public.viaturas(id),
  colaborador_id uuid references public.colaboradores(id),
  data date not null,
  descricao text not null,
  estado text not null default 'aberto' check (estado = any (array[
    'aberto'::text, 'em_seguradora'::text, 'fechado'::text
  ])),
  criado_em timestamptz not null default now()
);

create table if not exists public.viaturas_sinistros_anexos (
  id uuid primary key default gen_random_uuid(),
  sinistro_id uuid not null references public.viaturas_sinistros(id) on delete cascade,
  arquivo_url text not null,
  nome_arquivo text not null,
  criado_em timestamptz not null default now()
);

create table if not exists public.multas (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores(id),
  viatura_id uuid references public.viaturas(id),
  data date not null,
  descricao text,
  valor numeric,
  criado_em timestamptz not null default now()
);

create table if not exists public.multas_anexos (
  id uuid primary key default gen_random_uuid(),
  multa_id uuid not null references public.multas(id) on delete cascade,
  arquivo_url text not null,
  nome_arquivo text not null,
  criado_em timestamptz not null default now()
);

create index if not exists viaturas_eventos_viatura_data_idx
  on public.viaturas_eventos (viatura_id, data desc);
create index if not exists viaturas_sinistros_viatura_data_idx
  on public.viaturas_sinistros (viatura_id, data desc);
create index if not exists multas_colaborador_data_idx
  on public.multas (colaborador_id, data desc);
create index if not exists multas_viatura_data_idx
  on public.multas (viatura_id, data desc) where viatura_id is not null;

grant select, insert on table
  public.viaturas_eventos,
  public.viaturas_sinistros,
  public.viaturas_sinistros_anexos,
  public.multas,
  public.multas_anexos
to authenticated;

alter table public.viaturas_eventos enable row level security;
alter table public.viaturas_sinistros enable row level security;
alter table public.viaturas_sinistros_anexos enable row level security;
alter table public.multas enable row level security;
alter table public.multas_anexos enable row level security;

drop policy if exists viaturas_eventos_select on public.viaturas_eventos;
create policy viaturas_eventos_select on public.viaturas_eventos
for select to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists viaturas_eventos_insert on public.viaturas_eventos;
create policy viaturas_eventos_insert on public.viaturas_eventos
for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists viaturas_sinistros_select on public.viaturas_sinistros;
create policy viaturas_sinistros_select on public.viaturas_sinistros
for select to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists viaturas_sinistros_insert on public.viaturas_sinistros;
create policy viaturas_sinistros_insert on public.viaturas_sinistros
for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists viaturas_sinistros_anexos_select on public.viaturas_sinistros_anexos;
create policy viaturas_sinistros_anexos_select on public.viaturas_sinistros_anexos
for select to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists viaturas_sinistros_anexos_insert on public.viaturas_sinistros_anexos;
create policy viaturas_sinistros_anexos_insert on public.viaturas_sinistros_anexos
for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists multas_select on public.multas;
create policy multas_select on public.multas
for select to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists multas_insert on public.multas;
create policy multas_insert on public.multas
for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists multas_anexos_select on public.multas_anexos;
create policy multas_anexos_select on public.multas_anexos
for select to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists multas_anexos_insert on public.multas_anexos;
create policy multas_anexos_insert on public.multas_anexos
for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_administrativo());

-- A pasta usada pelo frontend é documentos/rh/viatura ou
-- documentos/rh/colaborador, já abrangida pelas políticas privadas de RH.

create or replace function public.fn_verificar_alertas_seguro_viaturas()
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
    v.empresa_id,
    'seguro_viatura',
    'viaturas',
    v.id,
    'Seguro da viatura a vencer',
    concat_ws(' · ', nullif(v.marca_modelo, ''), nullif(v.matricula, ''),
      'seguro em ' || to_char(v.seguro_data, 'DD/MM/YYYY')),
    v.seguro_data,
    15,
    v.seguro_data - 15,
    'administrativo',
    'pendente'
  from public.viaturas v
  where v.seguro_data is not null
    and v.seguro_data - 15 <= current_date
    and not exists (
      select 1
      from public.alertas a
      where a.tipo = 'seguro_viatura'
        and a.entidade_tipo = 'viaturas'
        and a.entidade_id = v.id
        and a.antecedencia_dias = 15
        and a.data_evento_referencia = v.seguro_data
    );

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

revoke all on function public.fn_verificar_alertas_seguro_viaturas()
  from public, anon, authenticated;

-- Mantém o mesmo job diário: apenas alarga a função que esse job já chama.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_baselines jsonb := null;
  v_primeiras_consultas integer := 0;
  v_vencimentos integer := 0;
  v_seguros integer := 0;
begin
  if to_regprocedure('public.fn_verificar_congelamentos_pendentes()') is not null then
    execute 'select to_jsonb(public.fn_verificar_congelamentos_pendentes())'
      into v_baselines;
  end if;

  if to_regprocedure('public.fn_verificar_primeiras_consultas_medicina()') is not null then
    v_primeiras_consultas := public.fn_verificar_primeiras_consultas_medicina();
  end if;

  if to_regprocedure('public.fn_verificar_alertas_vencimento()') is not null then
    v_vencimentos := public.fn_verificar_alertas_vencimento();
  end if;

  v_seguros := public.fn_verificar_alertas_seguro_viaturas();

  return jsonb_build_object(
    'baselines', v_baselines,
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos,
    'alertas_seguro_criados', v_seguros
  );
end;
$$;

revoke all on function public.fn_executar_rotinas_diarias()
  from public, anon, authenticated;

-- Ativa já os seguros cujo limiar foi atingido.
select public.fn_verificar_alertas_seguro_viaturas();

commit;

select
  to_regclass('public.viaturas_eventos') is not null as eventos,
  to_regclass('public.viaturas_sinistros') is not null as sinistros,
  to_regclass('public.multas') is not null as multas,
  to_regprocedure('public.fn_verificar_alertas_seguro_viaturas()') is not null as alerta_seguro;
