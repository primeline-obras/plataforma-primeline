-- PRIMELINE | Índice de Pedidos de Prorrogação
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.
-- Migração aditiva e idempotente; não altera os cinco índices existentes.

begin;

create table if not exists public.pedidos_prorrogacao (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  tee_id uuid references public.alteracoes_tee(id) on delete set null,
  numero text,
  motivo text not null check (btrim(motivo) <> ''),
  dias_solicitados integer,
  data_pedido date,
  data_resposta date,
  estado text not null default 'pendente'
    check (estado in ('pendente', 'aprovado', 'recusado')),
  notas text
);

comment on table public.pedidos_prorrogacao is
  'Índice de pedidos de prorrogação independentes ou originados por um TEE.';

create index if not exists idx_pedidos_prorrogacao_obra_numero
  on public.pedidos_prorrogacao (obra_id, numero, data_pedido);
create index if not exists idx_pedidos_prorrogacao_tee
  on public.pedidos_prorrogacao (tee_id)
  where tee_id is not null;

create or replace function public.fn_validar_tee_pedido_prorrogacao()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.tee_id is not null and not exists (
    select 1 from public.alteracoes_tee t
    where t.id = new.tee_id and t.obra_id = new.obra_id
  ) then
    raise exception using errcode = '23514',
      message = 'O TEE de origem tem de pertencer à mesma obra do pedido de prorrogação.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_tee_pedido_prorrogacao
  on public.pedidos_prorrogacao;
create trigger trg_validar_tee_pedido_prorrogacao
before insert or update of obra_id, tee_id
on public.pedidos_prorrogacao
for each row execute function public.fn_validar_tee_pedido_prorrogacao();

alter table public.pedidos_prorrogacao enable row level security;
revoke all on table public.pedidos_prorrogacao from anon;
grant select, insert, update, delete on table public.pedidos_prorrogacao to authenticated;

drop policy if exists pl_pedidos_prorrogacao_select on public.pedidos_prorrogacao;
drop policy if exists pl_pedidos_prorrogacao_write on public.pedidos_prorrogacao;
create policy pl_pedidos_prorrogacao_select on public.pedidos_prorrogacao
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_pedidos_prorrogacao_write on public.pedidos_prorrogacao
for all to authenticated
using (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo())
with check (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo());

commit;
