-- PRIMELINE GO | Separação operacional de fornecedores e subempreiteiros por região
begin;

alter table public.fornecedores
  add column if not exists nif text,
  add column if not exists email text,
  add column if not exists telefone text,
  add column if not exists representante text,
  add column if not exists notas text;

create index if not exists fornecedores_nif_normalizado_idx
  on public.fornecedores ((regexp_replace(coalesce(nif, ''), '[^0-9A-Za-z]', '', 'g')))
  where nullif(btrim(nif), '') is not null;

create table if not exists public.fornecedores_zonas (
  id uuid primary key default gen_random_uuid(),
  fornecedor_id uuid not null references public.fornecedores(id) on delete cascade,
  zona text not null check (zona in ('lisboa_cascais', 'algarve')),
  criado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  unique (fornecedor_id, zona)
);

create index if not exists fornecedores_zonas_zona_idx
  on public.fornecedores_zonas (zona, fornecedor_id);

comment on table public.fornecedores_zonas is
  'Zonas em que cada fornecedor ou subempreiteiro trabalha. Um registo pode pertencer a Lisboa/Cascais, Algarve ou às duas.';

alter table public.fornecedores_zonas enable row level security;

revoke all on table public.fornecedores_zonas from public, anon;
grant select on table public.fornecedores_zonas to authenticated;

drop policy if exists fornecedores_zonas_select on public.fornecedores_zonas;
create policy fornecedores_zonas_select
on public.fornecedores_zonas
for select to authenticated
using (
  exists (
    select 1
    from public.fornecedores f
    join public.utilizadores u on u.id = public.fn_utilizador_atual_id()
    where f.id = fornecedor_id
      and f.empresa_id = u.empresa_id
      and coalesce(u.ativo, true)
  )
);

create or replace function public.fn_definir_zonas_fornecedor(
  p_fornecedor_id uuid,
  p_zonas text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_empresa_id uuid;
  v_zona text;
  v_zonas text[] := coalesce(p_zonas, '{}'::text[]);
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode classificar zonas.' using errcode = '42501';
  end if;

  select f.empresa_id into v_empresa_id
  from public.fornecedores f
  join public.utilizadores u on u.id = public.fn_utilizador_atual_id()
  where f.id = p_fornecedor_id
    and f.empresa_id = u.empresa_id
    and coalesce(u.ativo, true)
  for update of f;

  if not found then
    raise exception 'Fornecedor inexistente ou fora da sua empresa.';
  end if;

  if exists (
    select 1 from unnest(v_zonas) zona
    where zona not in ('lisboa_cascais', 'algarve')
  ) then
    raise exception 'Zona inválida. Use apenas Lisboa/Cascais ou Algarve.';
  end if;

  delete from public.fornecedores_zonas
  where fornecedor_id = p_fornecedor_id
    and not (zona = any(v_zonas));

  foreach v_zona in array v_zonas loop
    insert into public.fornecedores_zonas (fornecedor_id, zona, criado_por)
    values (p_fornecedor_id, v_zona, public.fn_utilizador_atual_id())
    on conflict (fornecedor_id, zona) do nothing;
  end loop;

  return jsonb_build_object(
    'fornecedor_id', p_fornecedor_id,
    'zonas', coalesce((
      select jsonb_agg(fz.zona order by fz.zona)
      from public.fornecedores_zonas fz
      where fz.fornecedor_id = p_fornecedor_id
    ), '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.fn_definir_zonas_fornecedor(uuid, text[])
from public, anon;
grant execute on function public.fn_definir_zonas_fornecedor(uuid, text[])
to authenticated;

create or replace function public.fn_editar_fornecedor_diretorio(
  p_fornecedor_id uuid,
  p_nome text,
  p_nif text,
  p_email text,
  p_telefone text,
  p_representante text,
  p_notas text,
  p_estado_confianca text
)
returns public.fornecedores
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fornecedor public.fornecedores;
  v_empresa_id uuid;
  v_nif_normalizado text := nullif(regexp_replace(coalesce(p_nif, ''), '[^0-9A-Za-z]', '', 'g'), '');
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode editar fornecedores.' using errcode = '42501';
  end if;
  if nullif(btrim(p_nome), '') is null then
    raise exception 'O nome do fornecedor é obrigatório.';
  end if;
  if nullif(btrim(p_email), '') is not null and position('@' in btrim(p_email)) < 2 then
    raise exception 'O email indicado não é válido.';
  end if;

  select f.empresa_id into v_empresa_id
  from public.fornecedores f
  join public.utilizadores u on u.id = public.fn_utilizador_atual_id()
  where f.id = p_fornecedor_id
    and f.empresa_id = u.empresa_id
    and coalesce(u.ativo, true)
  for update of f;
  if not found then
    raise exception 'Fornecedor inexistente ou fora da sua empresa.';
  end if;

  if v_nif_normalizado is not null and exists (
    select 1 from public.fornecedores f
    where f.empresa_id = v_empresa_id
      and f.id <> p_fornecedor_id
      and regexp_replace(coalesce(f.nif, ''), '[^0-9A-Za-z]', '', 'g') = v_nif_normalizado
  ) then
    raise exception 'Já existe outra empresa com este NIF. Reveja os possíveis duplicados antes de guardar.';
  end if;

  update public.fornecedores
  set nome = btrim(p_nome),
      nif = nullif(btrim(p_nif), ''),
      email = nullif(lower(btrim(p_email)), ''),
      telefone = nullif(btrim(p_telefone), ''),
      representante = nullif(btrim(p_representante), ''),
      notas = nullif(btrim(p_notas), ''),
      estado_confianca = coalesce(nullif(btrim(p_estado_confianca), ''), estado_confianca)
  where id = p_fornecedor_id
  returning * into v_fornecedor;

  return v_fornecedor;
end;
$function$;

revoke all on function public.fn_editar_fornecedor_diretorio(
  uuid, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.fn_editar_fornecedor_diretorio(
  uuid, text, text, text, text, text, text, text
) to authenticated;

do $block$
begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_fornecedores_zonas on public.fornecedores_zonas;
    create trigger trg_auditoria_fornecedores_zonas
    after insert or update or delete on public.fornecedores_zonas
    for each row execute function public.fn_registar_log_auditoria('id');
  end if;
end;
$block$;

commit;

select
  to_regprocedure('public.fn_definir_zonas_fornecedor(uuid,text[])') is not null as classificacao_zonas_ativa,
  to_regprocedure('public.fn_editar_fornecedor_diretorio(uuid,text,text,text,text,text,text,text)') is not null as edicao_cadastro_ativa,
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'fornecedores_zonas'
      and policyname = 'fornecedores_zonas_select'
  ) as leitura_zonas_protegida,
  (select count(*) from public.fornecedores f
   where not exists (select 1 from public.fornecedores_zonas z where z.fornecedor_id = f.id)) as fornecedores_por_classificar;
