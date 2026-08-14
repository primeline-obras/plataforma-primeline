begin;

create table if not exists public.feriados_empresa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  data date not null,
  nome text not null,
  ambito text not null check (ambito in ('nacional', 'municipal')),
  municipio text,
  folga boolean not null default true,
  atualizado_por uuid references public.utilizadores(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check ((ambito = 'nacional' and municipio is null) or (ambito = 'municipal' and municipio in ('Sintra', 'Cascais'))),
  unique nulls not distinct (empresa_id, data, ambito, municipio)
);

create or replace function public.fn_marcar_atualizacao_feriado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.atualizado_em := now();
  select u.id into new.atualizado_por
  from public.utilizadores u
  where u.auth_user_id = auth.uid() and coalesce(u.ativo, true)
  limit 1;
  return new;
end;
$$;

drop trigger if exists trg_marcar_atualizacao_feriado on public.feriados_empresa;
create trigger trg_marcar_atualizacao_feriado
before insert or update on public.feriados_empresa
for each row execute function public.fn_marcar_atualizacao_feriado();

alter table public.feriados_empresa enable row level security;
grant select, insert, update, delete on public.feriados_empresa to authenticated;

drop policy if exists feriados_empresa_select on public.feriados_empresa;
create policy feriados_empresa_select on public.feriados_empresa
for select to authenticated using (true);

drop policy if exists feriados_empresa_write on public.feriados_empresa;
create policy feriados_empresa_write on public.feriados_empresa
for all to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo())
with check (public.fn_e_admin() or public.fn_e_administrativo());

-- Calendário oficial de 2026: feriados nacionais, Sintra e Cascais.
insert into public.feriados_empresa (empresa_id, data, nome, ambito, municipio, folga)
select e.id, h.data, h.nome, h.ambito, h.municipio, true
from public.empresas e
cross join (values
  ('2026-01-01'::date, 'Ano Novo', 'nacional', null::text),
  ('2026-04-03'::date, 'Sexta-feira Santa', 'nacional', null::text),
  ('2026-04-05'::date, 'Domingo de Páscoa', 'nacional', null::text),
  ('2026-04-25'::date, 'Dia da Liberdade', 'nacional', null::text),
  ('2026-05-01'::date, 'Dia do Trabalhador', 'nacional', null::text),
  ('2026-06-04'::date, 'Corpo de Deus', 'nacional', null::text),
  ('2026-06-10'::date, 'Dia de Portugal', 'nacional', null::text),
  ('2026-08-15'::date, 'Assunção de Nossa Senhora', 'nacional', null::text),
  ('2026-10-05'::date, 'Implantação da República', 'nacional', null::text),
  ('2026-11-01'::date, 'Dia de Todos os Santos', 'nacional', null::text),
  ('2026-12-01'::date, 'Restauração da Independência', 'nacional', null::text),
  ('2026-12-08'::date, 'Imaculada Conceição', 'nacional', null::text),
  ('2026-12-25'::date, 'Natal', 'nacional', null::text),
  ('2026-06-29'::date, 'Feriado Municipal de Sintra', 'municipal', 'Sintra'),
  ('2026-06-13'::date, 'Feriado Municipal de Cascais', 'municipal', 'Cascais')
) as h(data, nome, ambito, municipio)
on conflict (empresa_id, data, ambito, municipio) do nothing;

commit;

select data, nome, ambito, municipio, folga
from public.feriados_empresa
where extract(year from data) = 2026
order by data, ambito, municipio;
