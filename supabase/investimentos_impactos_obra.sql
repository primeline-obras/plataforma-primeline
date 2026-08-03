-- PRIMELINE | Obras de investimento próprio
--
-- Migração de referência para manter o repositório alinhado com alterações já
-- aplicadas diretamente no Supabase em 03/08/2026. Não precisa de ser executada
-- no projeto atual. É idempotente para permitir reconstruir um ambiente novo.

begin;

create table if not exists public.investimentos (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) unique,
  orcamento_inicial_sem_iva numeric,
  orcamento_inicial_com_iva numeric,
  orcamento_revisto_sem_iva numeric,
  orcamento_revisto_com_iva numeric,
  criado_em timestamptz not null default now()
);

create table if not exists public.impactos_obra (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id),
  numero text not null,
  data date not null,
  tipo_impacto text not null,
  origem text,
  fase_id uuid references public.fases(id),
  especialidade text,
  descricao text not null,
  causa text,
  responsavel text,
  valor_sem_iva numeric,
  valor_iva numeric,
  valor_com_iva numeric,
  iva_dedutivel text check (iva_dedutivel = any (array['sim'::text, 'nao'::text, 'na'::text])),
  valor_iva_nao_dedutivel numeric,
  criado_em timestamptz not null default now(),
  unique (obra_id, numero)
);

alter table public.investimentos enable row level security;
alter table public.impactos_obra enable row level security;

revoke all on table public.investimentos from anon;
revoke all on table public.impactos_obra from anon;
grant select, insert on table public.investimentos to authenticated;
grant select, insert on table public.impactos_obra to authenticated;

drop policy if exists investimentos_select on public.investimentos;
create policy investimentos_select
on public.investimentos for select to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists investimentos_write on public.investimentos;
create policy investimentos_write
on public.investimentos for insert to authenticated
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists impactos_obra_select on public.impactos_obra;
create policy impactos_obra_select
on public.impactos_obra for select to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists impactos_obra_write on public.impactos_obra;
create policy impactos_obra_write
on public.impactos_obra for insert to authenticated
with check (public.fn_pode_editar_obra(obra_id));

update public.obras
set modalidade = 'investimento_proprio'
where id = '5222b4c4-5255-4269-bd76-72b5227989c0'::uuid
  and modalidade is distinct from 'investimento_proprio';

commit;
