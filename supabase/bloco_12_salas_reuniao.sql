-- Bloco 12 — Salas de Reunião
-- Migração idempotente: pode ser executada novamente sem duplicar a sala.

create table if not exists public.salas_reuniao (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nome text not null,
  criado_em timestamptz not null default now()
);

insert into public.salas_reuniao (empresa_id, nome)
select '73fb13c8-d29f-4192-a506-4ca243343add'::uuid, 'Sala de Reuniões'
where exists (
  select 1 from public.empresas
  where id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid
)
and not exists (
  select 1 from public.salas_reuniao
  where empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid
    and nome = 'Sala de Reuniões'
);

create table if not exists public.reservas_salas (
  id uuid primary key default gen_random_uuid(),
  sala_id uuid not null references public.salas_reuniao(id),
  titulo text not null,
  data date not null,
  hora_inicio time not null,
  hora_fim time not null,
  criado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  constraint reservas_salas_horario_valido check (hora_fim > hora_inicio)
);

create or replace function public.fn_bloquear_reserva_sobreposta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.reservas_salas r
    where r.sala_id = new.sala_id
      and r.data = new.data
      and r.id is distinct from new.id
      and (new.hora_inicio, new.hora_fim) overlaps (r.hora_inicio, r.hora_fim)
  ) then
    raise exception 'Já existe uma reserva para esta sala neste horário.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bloquear_reserva_sobreposta on public.reservas_salas;
create trigger trg_bloquear_reserva_sobreposta
before insert or update on public.reservas_salas
for each row execute function public.fn_bloquear_reserva_sobreposta();

alter table public.salas_reuniao enable row level security;
alter table public.reservas_salas enable row level security;

grant select on public.salas_reuniao to authenticated;
grant select, insert on public.reservas_salas to authenticated;

drop policy if exists salas_reuniao_select on public.salas_reuniao;
create policy salas_reuniao_select
on public.salas_reuniao for select to authenticated
using (true);

drop policy if exists reservas_salas_select on public.reservas_salas;
create policy reservas_salas_select
on public.reservas_salas for select to authenticated
using (true);

drop policy if exists reservas_salas_insert on public.reservas_salas;
create policy reservas_salas_insert
on public.reservas_salas for insert to authenticated
with check (true);

-- Verificação final: devolve uma linha com os quatro pontos essenciais.
select
  to_regclass('public.salas_reuniao') is not null as tabela_salas,
  to_regclass('public.reservas_salas') is not null as tabela_reservas,
  exists (
    select 1 from pg_trigger
    where tgname = 'trg_bloquear_reserva_sobreposta' and not tgisinternal
  ) as bloqueio_sobreposicao,
  exists (
    select 1 from public.salas_reuniao
    where empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid
      and nome = 'Sala de Reuniões'
  ) as sala_criada;
