begin;

create table if not exists public.projetos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nome text not null,
  cliente text,
  morada text,
  criado_em timestamptz not null default now()
);

create unique index if not exists projetos_empresa_nome_uidx
  on public.projetos (empresa_id, lower(nome));

alter table public.obras
  add column if not exists projeto_id uuid references public.projetos(id) on delete set null;

create index if not exists obras_projeto_id_idx on public.obras(projeto_id);

alter table public.projetos enable row level security;
revoke all on table public.projetos from anon;
grant select on table public.projetos to authenticated;
grant insert, update, delete on table public.projetos to authenticated;

drop policy if exists projetos_select on public.projetos;
create policy projetos_select
on public.projetos for select to authenticated
using (
  public.fn_e_admin()
  or public.fn_e_administrativo()
  or public.fn_e_financeiro()
  or exists (
    select 1
    from public.obras o
    where o.projeto_id = projetos.id
      and public.fn_pode_ver_obra(o.id)
  )
);

drop policy if exists projetos_insert on public.projetos;
create policy projetos_insert
on public.projetos for insert to authenticated
with check (public.fn_e_admin());

drop policy if exists projetos_update on public.projetos;
create policy projetos_update
on public.projetos for update to authenticated
using (public.fn_e_admin())
with check (public.fn_e_admin());

drop policy if exists projetos_delete on public.projetos;
create policy projetos_delete
on public.projetos for delete to authenticated
using (public.fn_e_admin());

-- Primeiro agrupamento confirmado. A Obra 128 será associada no formulário
-- quando for criada; esta migração não inventa dados da nova obra.
insert into public.projetos (empresa_id, nome, cliente, morada)
select o.empresa_id, 'Av. Bombeiros Voluntários', o.cliente, o.morada
from public.obras o
where o.numero::text = '122'
on conflict do nothing;

update public.obras o
set projeto_id = p.id
from public.projetos p
where o.numero::text = '122'
  and p.empresa_id = o.empresa_id
  and lower(p.nome) = lower('Av. Bombeiros Voluntários')
  and o.projeto_id is distinct from p.id;

commit;

select
  p.nome as projeto,
  count(o.id) as etapas_associadas,
  string_agg(o.numero::text || ' — ' || o.nome, ' | ' order by o.numero::text) as etapas
from public.projetos p
left join public.obras o on o.projeto_id = p.id
where lower(p.nome) = lower('Av. Bombeiros Voluntários')
group by p.id, p.nome;
