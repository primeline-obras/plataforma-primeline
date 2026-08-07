-- PRIMELINE | Bloco 10 - cruzamento RH, obra e financeiro.
-- Preserva os acessos existentes e nao cria alertas de percurso de fatura.

begin;

-- Autor do lancamento: os registos antigos permanecem com autor nulo quando
-- nao existe informacao segura para o reconstruir.
alter table public.faturas
  add column if not exists criado_por uuid;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.faturas'::regclass
      and conname = 'faturas_criado_por_fkey'
  ) then
    alter table public.faturas
      add constraint faturas_criado_por_fkey
      foreign key (criado_por) references public.utilizadores(id);
  end if;
end;
$block$;

create or replace function public.fn_registar_percurso_fatura()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_op = 'INSERT' then
    new.criado_por := coalesce(
      new.criado_por,
      public.fn_utilizador_atual_id()
    );
  end if;

  if tg_op = 'UPDATE'
     and new.estado_aprovacao is distinct from old.estado_aprovacao then
    new.aprovado_por := public.fn_utilizador_atual_id();
    new.data_aprovacao := coalesce(new.data_aprovacao, now());
  end if;

  if tg_op = 'UPDATE'
     and new.estado_pagamento = 'pago'
     and new.estado_pagamento is distinct from old.estado_pagamento then
    new.pago_por := public.fn_utilizador_atual_id();
    new.data_pagamento := coalesce(new.data_pagamento, current_date);
  end if;

  return new;
end;
$function$;

revoke all
on function public.fn_registar_percurso_fatura()
from public, anon, authenticated;

drop trigger if exists trg_registar_percurso_fatura
  on public.faturas;

create trigger trg_registar_percurso_fatura
before insert or update of estado_aprovacao, estado_pagamento
on public.faturas
for each row
execute function public.fn_registar_percurso_fatura();

create index if not exists faturas_percurso_data_idx
  on public.faturas (criado_em desc, estado_aprovacao, estado_pagamento);

-- RPC de leitura: junta os nomes dos intervenientes sem alargar a leitura
-- direta da tabela utilizadores.
create or replace function public.fn_listar_rastreio_faturas()
returns table (
  id uuid,
  obra_id uuid,
  obra_numero text,
  obra_nome text,
  fornecedor_nome text,
  numero_doc text,
  valor numeric,
  estado_aprovacao text,
  estado_pagamento text,
  criado_em timestamptz,
  criado_por uuid,
  criado_por_nome text,
  data_aprovacao timestamptz,
  aprovado_por uuid,
  aprovado_por_nome text,
  data_pagamento date,
  pago_por uuid,
  pago_por_nome text
)
language sql
stable
security definer
set search_path = public
as $function$
  select
    f.id,
    f.obra_id,
    o.numero::text,
    o.nome,
    fr.nome,
    f.numero_doc,
    f.valor,
    f.estado_aprovacao,
    f.estado_pagamento,
    f.criado_em,
    f.criado_por,
    uc.nome,
    f.data_aprovacao,
    f.aprovado_por,
    ua.nome,
    f.data_pagamento,
    f.pago_por,
    up.nome
  from public.faturas f
  join public.obras o on o.id = f.obra_id
  left join public.fornecedores fr on fr.id = f.fornecedor_id
  left join public.utilizadores uc on uc.id = f.criado_por
  left join public.utilizadores ua on ua.id = f.aprovado_por
  left join public.utilizadores up on up.id = f.pago_por
  where public.fn_e_admin()
     or public.fn_e_administrativo()
     or public.fn_e_financeiro()
     or public.fn_pode_ver_obra(f.obra_id)
  order by f.criado_em desc, f.id;
$function$;

revoke all
on function public.fn_listar_rastreio_faturas()
from public, anon;

grant execute
on function public.fn_listar_rastreio_faturas()
to authenticated;

-- A obra atual corresponde estritamente a ultima alocacao ate hoje. Alocacoes
-- futuras nao antecipam acessos. Se a ultima for Garantia/Pontual sem obra_id,
-- nao se recua para uma obra antiga.
create or replace function public.fn_colaborador_na_obra_atual_encarregado(
  p_colaborador_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_obra_id uuid;
begin
  select q.obra_id
    into v_obra_id
  from public.quadro_pessoal_alocacao q
  where q.colaborador_id = p_colaborador_id
    and q.data <= current_date
  order by
    q.data desc nulls last,
    q.criado_em desc nulls last,
    q.id desc
  limit 1;

  return v_obra_id is not null
    and public.fn_e_encarregado_da_obra(v_obra_id);
end;
$function$;

revoke all
on function public.fn_colaborador_na_obra_atual_encarregado(uuid)
from public, anon;

grant execute
on function public.fn_colaborador_na_obra_atual_encarregado(uuid)
to authenticated;

grant select on table public.medicina_trabalho to authenticated;
grant select on table public.ausencias to authenticated;

drop policy if exists pl_medicina_encarregado_atual_select
  on public.medicina_trabalho;

create policy pl_medicina_encarregado_atual_select
on public.medicina_trabalho
for select
to authenticated
using (
  public.fn_colaborador_na_obra_atual_encarregado(colaborador_id)
);

drop policy if exists pl_ausencias_ferias_encarregado_atual_select
  on public.ausencias;

create policy pl_ausencias_ferias_encarregado_atual_select
on public.ausencias
for select
to authenticated
using (
  tipo = 'ferias'
  and public.fn_colaborador_na_obra_atual_encarregado(colaborador_id)
);

commit;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'faturas'
      and column_name = 'criado_por'
  ) as autor_lancamento,
  to_regprocedure(
    'public.fn_listar_rastreio_faturas()'
  ) is not null as rastreio_faturas,
  to_regprocedure(
    'public.fn_colaborador_na_obra_atual_encarregado(uuid)'
  ) is not null as obra_atual_colaborador,
  count(*) filter (
    where tablename = 'medicina_trabalho'
      and policyname = 'pl_medicina_encarregado_atual_select'
  ) as politica_medicina,
  count(*) filter (
    where tablename = 'ausencias'
      and policyname = 'pl_ausencias_ferias_encarregado_atual_select'
  ) as politica_ferias
from pg_policies
where schemaname = 'public';
