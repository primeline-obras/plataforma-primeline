begin;

alter table public.especialidades
  add column if not exists aplicavel_subempreiteiro boolean not null default false;

-- Classificação muitos-para-muitos. Os textos históricos das consultas e
-- subempreitadas não são alterados: continuam a constituir o registo original.
create table if not exists public.fornecedores_especialidades (
  id uuid primary key default gen_random_uuid(),
  fornecedor_id uuid not null references public.fornecedores(id) on delete cascade,
  especialidade_id uuid not null references public.especialidades(id) on delete cascade,
  origem text not null default 'manual'
    check (origem = any (array['manual'::text, 'historico'::text])),
  criado_por uuid references public.utilizadores(id) on delete set null,
  criado_em timestamptz not null default now(),
  unique (fornecedor_id, especialidade_id)
);

create table if not exists public.especialidades_aliases (
  id uuid primary key default gen_random_uuid(),
  especialidade_id uuid not null references public.especialidades(id) on delete cascade,
  alias text not null,
  criado_em timestamptz not null default now()
);

create unique index if not exists especialidades_aliases_alias_especialidade_ci_key
  on public.especialidades_aliases (lower(trim(alias)), especialidade_id);
create index if not exists fornecedores_especialidades_fornecedor_idx
  on public.fornecedores_especialidades (fornecedor_id);
create index if not exists fornecedores_especialidades_especialidade_idx
  on public.fornecedores_especialidades (especialidade_id);

-- Ajusta três entradas gerais já existentes para os nomes oficiais aprovados.
update public.especialidades
set nome = 'AVAC / CLIMATIZAÇÃO'
where upper(trim(nome)) = 'CLIMATIZAÇÃO'
  and not exists (select 1 from public.especialidades where upper(trim(nome)) = 'AVAC / CLIMATIZAÇÃO');

update public.especialidades
set nome = 'CANALIZAÇÃO E HIDRÁULICA'
where upper(trim(nome)) = 'CANALIZADOR'
  and not exists (select 1 from public.especialidades where upper(trim(nome)) = 'CANALIZAÇÃO E HIDRÁULICA');

update public.especialidades
set nome = 'CANTARIAS'
where upper(trim(nome)) = 'CANTARIAS E BANCADAS DE COZINHA'
  and not exists (select 1 from public.especialidades where upper(trim(nome)) = 'CANTARIAS');

insert into public.especialidades (nome)
select nome
from (values
  ('AVAC / CLIMATIZAÇÃO'),
  ('CANALIZAÇÃO E HIDRÁULICA'),
  ('CANTARIAS'),
  ('EQUIPAMENTOS DE COZINHA')
) as novas(nome)
where not exists (
  select 1 from public.especialidades e where upper(trim(e.nome)) = upper(trim(novas.nome))
);

update public.especialidades
set aplicavel_subempreiteiro = true
where upper(trim(nome)) = any (array[
  'AVAC / CLIMATIZAÇÃO',
  'CANALIZAÇÃO E HIDRÁULICA',
  'INSTALAÇÕES ELÉTRICAS',
  'INSTALAÇÃO DE GÁS',
  'BETONILHAS E ENCHIMENTO',
  'CAIXILHARIAS',
  'CANTARIAS',
  'CARPINTARIAS',
  'IMPERMEABILIZAÇÕES',
  'SERVENTES',
  'PINTURAS',
  'PAVIMENTOS E REVESTIMENTOS',
  'REVESTIMENTOS EM PEDRA',
  'SERRALHARIAS',
  'SOLUÇÕES EM INOX',
  'MOVIMENTO DE TERRAS',
  'VIDROS E ESPELHOS',
  'EQUIPAMENTOS DE COZINHA'
]);

-- Alias revistos pela Jordane. Um texto pode apontar para mais de uma
-- especialidade apenas através da carga histórica abaixo (caso Pintura/Revestimentos).
with mapa(alias, oficial) as (values
  ('AC Pré-instalação', 'AVAC / CLIMATIZAÇÃO'),
  ('AVAC / Climatização', 'AVAC / CLIMATIZAÇÃO'),
  ('VMC', 'AVAC / CLIMATIZAÇÃO'),
  ('Piso Radiante', 'AVAC / CLIMATIZAÇÃO'),
  ('Equipamentos (Aquecedor de parede — em comparação)', 'AVAC / CLIMATIZAÇÃO'),
  ('AQS', 'CANALIZAÇÃO E HIDRÁULICA'),
  ('Hidráulica', 'CANALIZAÇÃO E HIDRÁULICA'),
  ('Elétrica', 'INSTALAÇÕES ELÉTRICAS'),
  ('Eletricidade', 'INSTALAÇÕES ELÉTRICAS'),
  ('Gás', 'INSTALAÇÃO DE GÁS'),
  ('Betonilha', 'BETONILHAS E ENCHIMENTO'),
  ('Caixilharia', 'CAIXILHARIAS'),
  ('Cantaria', 'CANTARIAS'),
  ('Carpintaria', 'CARPINTARIAS'),
  ('Impermeabilização', 'IMPERMEABILIZAÇÕES'),
  ('Mão de obra de servente (apoio geral)', 'SERVENTES'),
  ('Pintura', 'PINTURAS'),
  ('Revestimentos Pavimento', 'PAVIMENTOS E REVESTIMENTOS'),
  ('Revestimentos Pavimento (Microcimento)', 'PAVIMENTOS E REVESTIMENTOS'),
  ('Revestimentos Parede (Pedroso & Osorio — em análise)', 'PAVIMENTOS E REVESTIMENTOS'),
  ('Revestimentos / Pintura', 'PAVIMENTOS E REVESTIMENTOS'),
  ('Revestimentos / Pintura', 'PINTURAS'),
  ('Pedras / Revestimentos (Ricardo Miguel — em análise)', 'REVESTIMENTOS EM PEDRA'),
  ('Serralharia', 'SERRALHARIAS'),
  ('Serralharia / Inox', 'SERRALHARIAS'),
  ('Serralharia / Inox', 'SOLUÇÕES EM INOX'),
  ('Vala', 'MOVIMENTO DE TERRAS'),
  ('Vidros / Espelhos', 'VIDROS E ESPELHOS'),
  ('Equipamentos Cozinha (Haier — em comparação)', 'EQUIPAMENTOS DE COZINHA')
), resolvido as (
  select m.alias, e.id as especialidade_id
  from mapa m
  join public.especialidades e on upper(trim(e.nome)) = upper(trim(m.oficial))
)
insert into public.especialidades_aliases (especialidade_id, alias)
select especialidade_id, alias from resolvido
on conflict ((lower(trim(alias))), especialidade_id) do nothing;

-- Classificação automática apenas a partir de relações históricas inequívocas.
with historico as (
  select s.fornecedor_id, a.especialidade_id
  from public.subempreitadas s
  join public.especialidades_aliases a on lower(trim(a.alias)) = lower(trim(s.especialidade))
  where s.fornecedor_id is not null
  union
  select c.fornecedor_id, a.especialidade_id
  from public.consultas_subempreitada_candidatos c
  join public.consultas_subempreitada q on q.id = c.consulta_subempreitada_id
  join public.especialidades_aliases a on lower(trim(a.alias)) = lower(trim(q.trabalho))
  where c.fornecedor_id is not null
)
insert into public.fornecedores_especialidades (fornecedor_id, especialidade_id, origem)
select fornecedor_id, especialidade_id, 'historico'
from historico
on conflict (fornecedor_id, especialidade_id) do nothing;

alter table public.fornecedores_especialidades enable row level security;
alter table public.especialidades_aliases enable row level security;

drop policy if exists fornecedores_especialidades_select on public.fornecedores_especialidades;
create policy fornecedores_especialidades_select
on public.fornecedores_especialidades for select to authenticated using (true);

drop policy if exists fornecedores_especialidades_write on public.fornecedores_especialidades;
create policy fornecedores_especialidades_write
on public.fornecedores_especialidades for all to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo())
with check (public.fn_e_admin() or public.fn_e_administrativo());

drop policy if exists especialidades_aliases_select on public.especialidades_aliases;
create policy especialidades_aliases_select
on public.especialidades_aliases for select to authenticated using (true);

drop policy if exists especialidades_aliases_write on public.especialidades_aliases;
create policy especialidades_aliases_write
on public.especialidades_aliases for all to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo())
with check (public.fn_e_admin() or public.fn_e_administrativo());

grant select on public.especialidades, public.especialidades_aliases,
  public.fornecedores_especialidades to authenticated;
grant insert, update, delete on public.fornecedores_especialidades,
  public.especialidades_aliases to authenticated;

commit;

select
  (select count(*) from public.especialidades_aliases) as aliases,
  (select count(*) from public.fornecedores_especialidades) as fornecedores_classificados,
  (select count(distinct fornecedor_id) from public.fornecedores_especialidades) as subempreiteiros_classificados;
