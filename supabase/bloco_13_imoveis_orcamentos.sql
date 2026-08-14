-- PRIMELINE | Bloco 13 — Imóveis, condomínio e pedidos de orçamento
-- Migração idempotente e integrada na rotina diária já existente.

begin;

create table if not exists public.imoveis_empresa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nome text not null,
  morada text,
  criado_em timestamptz not null default now()
);

create table if not exists public.imoveis_reunioes_condominio (
  id uuid primary key default gen_random_uuid(),
  imovel_id uuid not null references public.imoveis_empresa(id),
  data date not null,
  hora time,
  local text,
  notas text,
  criado_em timestamptz not null default now()
);

create table if not exists public.pedidos_orcamento (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  cliente_nome text not null,
  cliente_contacto text,
  intermediario text,
  descricao_trabalho text not null,
  data_limite_entrega date,
  estado text not null default 'em_curso'
    check (estado = any (array[
      'em_curso'::text, 'enviado'::text, 'aguarda_resposta'::text,
      'adjudicado'::text, 'recusado'::text, 'cancelado'::text
    ])),
  prioritario boolean not null default false,
  situacao_atual text,
  criado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now()
);

create table if not exists public.pedidos_orcamento_versoes (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references public.pedidos_orcamento(id) on delete cascade,
  data_envio date not null,
  valor numeric,
  notas text,
  criado_em timestamptz not null default now()
);

alter table public.imoveis_empresa enable row level security;
alter table public.imoveis_reunioes_condominio enable row level security;
alter table public.pedidos_orcamento enable row level security;
alter table public.pedidos_orcamento_versoes enable row level security;

grant select, insert on public.imoveis_empresa to authenticated;
grant select, insert on public.imoveis_reunioes_condominio to authenticated;
grant select, insert, update on public.pedidos_orcamento to authenticated;
grant select, insert on public.pedidos_orcamento_versoes to authenticated;

drop policy if exists imoveis_empresa_select on public.imoveis_empresa;
create policy imoveis_empresa_select on public.imoveis_empresa
for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists imoveis_empresa_insert on public.imoveis_empresa;
create policy imoveis_empresa_insert on public.imoveis_empresa
for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists imoveis_reunioes_select on public.imoveis_reunioes_condominio;
create policy imoveis_reunioes_select on public.imoveis_reunioes_condominio
for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists imoveis_reunioes_insert on public.imoveis_reunioes_condominio;
create policy imoveis_reunioes_insert on public.imoveis_reunioes_condominio
for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists pedidos_orcamento_select on public.pedidos_orcamento;
create policy pedidos_orcamento_select on public.pedidos_orcamento
for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists pedidos_orcamento_insert on public.pedidos_orcamento;
create policy pedidos_orcamento_insert on public.pedidos_orcamento
for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists pedidos_orcamento_update on public.pedidos_orcamento;
create policy pedidos_orcamento_update on public.pedidos_orcamento
for update to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo())
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists pedidos_orcamento_versoes_select on public.pedidos_orcamento_versoes;
create policy pedidos_orcamento_versoes_select on public.pedidos_orcamento_versoes
for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists pedidos_orcamento_versoes_insert on public.pedidos_orcamento_versoes;
create policy pedidos_orcamento_versoes_insert on public.pedidos_orcamento_versoes
for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());

create or replace function public.fn_verificar_alertas_imoveis_orcamentos(
  p_data date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_reunioes integer := 0;
  v_orcamentos integer := 0;
begin
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    i.empresa_id,
    'reuniao_condominio',
    'imoveis_reunioes_condominio',
    r.id,
    'Reunião de condomínio · ' || i.nome,
    'Reunião marcada para ' || to_char(r.data, 'DD/MM/YYYY')
      || case when r.hora is not null then ' às ' || to_char(r.hora, 'HH24:MI') else '' end
      || case when nullif(btrim(r.local), '') is not null then ' · ' || r.local else '' end,
    r.data,
    7,
    r.data - 7,
    'administrativo',
    'pendente'
  from public.imoveis_reunioes_condominio r
  join public.imoveis_empresa i on i.id = r.imovel_id
  where r.data >= p_data
    and r.data - 7 <= p_data
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'reuniao_condominio'
        and a.entidade_tipo = 'imoveis_reunioes_condominio'
        and a.entidade_id = r.id
        and a.antecedencia_dias = 7
        and a.data_evento_referencia = r.data
    );
  get diagnostics v_reunioes = row_count;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    p.empresa_id,
    'prazo_pedido_orcamento',
    'pedidos_orcamento',
    p.id,
    'Prazo de orçamento · ' || p.cliente_nome,
    'Entrega prevista para ' || to_char(p.data_limite_entrega, 'DD/MM/YYYY')
      || ' · ' || p.descricao_trabalho,
    p.data_limite_entrega,
    limiar.dias,
    p.data_limite_entrega - limiar.dias,
    'administrativo',
    'pendente'
  from public.pedidos_orcamento p
  cross join (values (15), (7), (3)) as limiar(dias)
  where p.estado = 'em_curso'
    and p.data_limite_entrega is not null
    and p.data_limite_entrega >= p_data
    and p.data_limite_entrega - limiar.dias <= p_data
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'prazo_pedido_orcamento'
        and a.entidade_tipo = 'pedidos_orcamento'
        and a.entidade_id = p.id
        and a.antecedencia_dias = limiar.dias
        and a.data_evento_referencia = p.data_limite_entrega
    );
  get diagnostics v_orcamentos = row_count;

  return jsonb_build_object(
    'reunioes_condominio_criadas', v_reunioes,
    'prazos_orcamento_criados', v_orcamentos
  );
end;
$function$;

revoke all on function public.fn_verificar_alertas_imoveis_orcamentos(date)
from public, anon, authenticated;

-- Mantém um único ponto de entrada para o job diário já configurado.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_baselines jsonb := null;
  v_primeiras_consultas integer := 0;
  v_vencimentos integer := 0;
  v_seguros integer := 0;
  v_pedidos_horas integer := 0;
  v_imoveis_orcamentos jsonb := '{}'::jsonb;
begin
  if to_regprocedure('public.fn_verificar_congelamentos_pendentes()') is not null then
    execute 'select to_jsonb(public.fn_verificar_congelamentos_pendentes())' into v_baselines;
  end if;
  if to_regprocedure('public.fn_verificar_primeiras_consultas_medicina()') is not null then
    v_primeiras_consultas := public.fn_verificar_primeiras_consultas_medicina();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_vencimento()') is not null then
    v_vencimentos := public.fn_verificar_alertas_vencimento();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_seguro_viaturas()') is not null then
    v_seguros := public.fn_verificar_alertas_seguro_viaturas();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_fim_contrato()') is not null then
    perform public.fn_verificar_alertas_fim_contrato();
  end if;
  if to_regprocedure('public.fn_criar_pedidos_horas_semanais(date)') is not null then
    v_pedidos_horas := public.fn_criar_pedidos_horas_semanais(current_date);
  end if;

  v_imoveis_orcamentos := public.fn_verificar_alertas_imoveis_orcamentos(current_date);

  return jsonb_build_object(
    'baselines', v_baselines,
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos,
    'alertas_seguro_criados', v_seguros,
    'contratos_trabalho_verificados', true,
    'pedidos_horas_criados', v_pedidos_horas,
    'imoveis_orcamentos', v_imoveis_orcamentos
  );
end;
$function$;

revoke all on function public.fn_executar_rotinas_diarias()
from public, anon, authenticated;

commit;

-- Executa uma primeira verificação e confirma a instalação.
select public.fn_verificar_alertas_imoveis_orcamentos(current_date);

select
  to_regclass('public.imoveis_empresa') is not null as imoveis,
  to_regclass('public.imoveis_reunioes_condominio') is not null as reunioes_condominio,
  to_regclass('public.pedidos_orcamento') is not null as pedidos_orcamento,
  to_regclass('public.pedidos_orcamento_versoes') is not null as versoes,
  to_regprocedure('public.fn_verificar_alertas_imoveis_orcamentos(date)') is not null as alertas,
  to_regprocedure('public.fn_executar_rotinas_diarias()') is not null as rotina_diaria;
