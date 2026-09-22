-- PRIMELINE GO | Consolidação segura de fornecedores/subempreiteiros duplicados.
-- A pré-visualização não altera dados. A confirmação transfere, numa única
-- transação, todas as referências protegidas por FK e preserva o nome antigo.

begin;

create table if not exists public.fornecedores_aliases (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  fornecedor_id uuid not null references public.fornecedores(id) on delete cascade,
  nome text not null,
  nome_normalizado text generated always as (lower(btrim(nome))) stored,
  nif text,
  email text,
  fornecedor_origem_id uuid,
  criado_por uuid references public.utilizadores(id) on delete set null,
  criado_em timestamptz not null default now(),
  unique (empresa_id, nome_normalizado)
);

create index if not exists fornecedores_aliases_fornecedor_idx
  on public.fornecedores_aliases(fornecedor_id);

alter table public.fornecedores_aliases
  add column if not exists nif text,
  add column if not exists email text;

create table if not exists public.fornecedores_mesclagens (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  fornecedor_origem_id uuid not null,
  fornecedor_destino_id uuid references public.fornecedores(id) on delete set null,
  nome_origem text not null,
  nome_destino text not null,
  impacto jsonb not null default '{}'::jsonb,
  executado_por uuid references public.utilizadores(id) on delete set null,
  executado_em timestamptz not null default now()
);

alter table public.faturas
  add column if not exists fornecedor_nome_original text;

create or replace function public.fn_previsualizar_mesclagem_fornecedor(
  p_fornecedor_origem_id uuid,
  p_fornecedor_destino_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_atual public.utilizadores;
  v_origem public.fornecedores;
  v_destino public.fornecedores;
  v_ref record;
  v_total bigint;
  v_total_referencias bigint := 0;
  v_referencias jsonb := '[]'::jsonb;
  v_conflitos jsonb := '[]'::jsonb;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode mesclar fornecedores.' using errcode = '42501';
  end if;
  if p_fornecedor_origem_id is null or p_fornecedor_destino_id is null
     or p_fornecedor_origem_id = p_fornecedor_destino_id then
    raise exception 'Escolha dois registos diferentes: o duplicado e o registo que será mantido.';
  end if;

  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and coalesce(ativo, true);
  select * into v_origem from public.fornecedores
  where id = p_fornecedor_origem_id and empresa_id = v_atual.empresa_id;
  select * into v_destino from public.fornecedores
  where id = p_fornecedor_destino_id and empresa_id = v_atual.empresa_id;
  if v_origem.id is null or v_destino.id is null then
    raise exception 'Um dos fornecedores não existe ou pertence a outra empresa.';
  end if;

  for v_ref in
    select c.conrelid::regclass as tabela, a.attname as coluna
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid = 'public.fornecedores'::regclass
      and array_length(c.conkey, 1) = 1
      and c.conrelid not in (
        'public.fornecedores_zonas'::regclass,
        'public.fornecedores_especialidades'::regclass,
        'public.fornecedores_aliases'::regclass
      )
  loop
    execute format('select count(*) from %s where %I = $1', v_ref.tabela, v_ref.coluna)
      into v_total using p_fornecedor_origem_id;
    if v_total > 0 then
      v_total_referencias := v_total_referencias + v_total;
      v_referencias := v_referencias || jsonb_build_array(jsonb_build_object(
        'tabela', v_ref.tabela::text, 'coluna', v_ref.coluna, 'registos', v_total
      ));
    end if;
  end loop;

  if to_regclass('public.comparativo_propostas') is not null then
    select count(*) into v_total
    from public.comparativo_propostas origem
    join public.comparativo_propostas destino
      on destino.mapa_id = origem.mapa_id
     and destino.fornecedor_id = p_fornecedor_destino_id
    where origem.fornecedor_id = p_fornecedor_origem_id;
    if v_total > 0 then
      v_conflitos := v_conflitos || jsonb_build_array(jsonb_build_object(
        'tipo', 'propostas_no_mesmo_mapa', 'registos', v_total,
        'mensagem', 'Os dois fornecedores têm propostas no mesmo mapa comparativo. Reveja essas propostas antes de mesclar.'
      ));
    end if;
  end if;

  select count(*) into v_total
  from public.faturas origem
  join public.faturas destino
    on destino.fornecedor_id = p_fornecedor_destino_id
   and lower(btrim(destino.numero_doc)) = lower(btrim(origem.numero_doc))
   and destino.id <> origem.id
  where origem.fornecedor_id = p_fornecedor_origem_id
    and nullif(btrim(origem.numero_doc), '') is not null;
  if v_total > 0 then
    v_conflitos := v_conflitos || jsonb_build_array(jsonb_build_object(
      'tipo', 'faturas_com_mesmo_numero', 'registos', v_total,
      'mensagem', 'Existem faturas com o mesmo número nos dois registos. Resolva essas duplicações antes de mesclar.'
    ));
  end if;

  return jsonb_build_object(
    'origem', jsonb_build_object('id', v_origem.id, 'nome', v_origem.nome, 'nif', v_origem.nif),
    'destino', jsonb_build_object('id', v_destino.id, 'nome', v_destino.nome, 'nif', v_destino.nif),
    'total_referencias', v_total_referencias,
    'referencias', v_referencias,
    'conflitos', v_conflitos,
    'pode_mesclar', jsonb_array_length(v_conflitos) = 0
  );
end;
$function$;

revoke all on function public.fn_previsualizar_mesclagem_fornecedor(uuid, uuid)
  from public, anon;
grant execute on function public.fn_previsualizar_mesclagem_fornecedor(uuid, uuid)
  to authenticated;

-- A alteração do fornecedor durante a mesclagem é deliberada. O bloqueio normal
-- de faturas duplicadas continua ativo em todos os restantes fluxos.
create or replace function public.fn_bloquear_fatura_duplicada()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if current_setting('app.mesclagem_fornecedor', true) = 'on' or public.fn_e_admin() then
    return new;
  end if;
  if exists (
    select 1 from public.faturas f
    where f.fornecedor_id = new.fornecedor_id
      and lower(btrim(f.numero_doc)) = lower(btrim(new.numero_doc))
      and f.id is distinct from new.id
  ) then
    raise exception 'Já existe uma fatura com este número para este fornecedor — possível duplicação.';
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_bloquear_fatura_duplicada()
  from public, anon, authenticated;

create or replace function public.fn_mesclar_fornecedor(
  p_fornecedor_origem_id uuid,
  p_fornecedor_destino_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_atual public.utilizadores;
  v_origem public.fornecedores;
  v_destino public.fornecedores;
  v_previa jsonb;
  v_ref record;
  v_movidos bigint;
  v_total_movidos bigint := 0;
  v_impacto jsonb := '{}'::jsonb;
  v_tipo text;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode mesclar fornecedores.' using errcode = '42501';
  end if;

  v_previa := public.fn_previsualizar_mesclagem_fornecedor(
    p_fornecedor_origem_id, p_fornecedor_destino_id
  );
  if not coalesce((v_previa ->> 'pode_mesclar')::boolean, false) then
    raise exception 'A mesclagem tem conflitos que precisam de revisão: %', v_previa -> 'conflitos';
  end if;

  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and coalesce(ativo, true);
  select * into v_origem from public.fornecedores
  where id = p_fornecedor_origem_id and empresa_id = v_atual.empresa_id
  for update;
  select * into v_destino from public.fornecedores
  where id = p_fornecedor_destino_id and empresa_id = v_atual.empresa_id
  for update;
  if v_origem.id is null or v_destino.id is null then
    raise exception 'Um dos fornecedores deixou de estar disponível. Atualize a página.';
  end if;

  perform set_config('app.mesclagem_fornecedor', 'on', true);

  update public.faturas
  set fornecedor_nome_original = coalesce(nullif(fornecedor_nome_original, ''), v_origem.nome)
  where fornecedor_id = p_fornecedor_origem_id;

  insert into public.fornecedores_zonas(fornecedor_id, zona, criado_por)
  select p_fornecedor_destino_id, zona, coalesce(criado_por, v_atual.id)
  from public.fornecedores_zonas where fornecedor_id = p_fornecedor_origem_id
  on conflict (fornecedor_id, zona) do nothing;

  insert into public.fornecedores_especialidades(fornecedor_id, especialidade_id, origem, criado_por)
  select p_fornecedor_destino_id, especialidade_id, origem, coalesce(criado_por, v_atual.id)
  from public.fornecedores_especialidades where fornecedor_id = p_fornecedor_origem_id
  on conflict (fornecedor_id, especialidade_id) do nothing;

  update public.fornecedores_aliases
  set fornecedor_id = p_fornecedor_destino_id
  where fornecedor_id = p_fornecedor_origem_id;

  insert into public.fornecedores_aliases(
    empresa_id, fornecedor_id, nome, nif, email, fornecedor_origem_id, criado_por
  ) values (
    v_atual.empresa_id, p_fornecedor_destino_id, v_origem.nome, v_origem.nif, v_origem.email,
    p_fornecedor_origem_id, v_atual.id
  ) on conflict (empresa_id, nome_normalizado) do nothing;
  delete from public.fornecedores_zonas where fornecedor_id = p_fornecedor_origem_id;
  delete from public.fornecedores_especialidades where fornecedor_id = p_fornecedor_origem_id;

  for v_ref in
    select c.conrelid::regclass as tabela, a.attname as coluna
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid = 'public.fornecedores'::regclass
      and array_length(c.conkey, 1) = 1
      and c.conrelid not in (
        'public.fornecedores_zonas'::regclass,
        'public.fornecedores_especialidades'::regclass,
        'public.fornecedores_aliases'::regclass
      )
  loop
    execute format('update %s set %I = $1 where %I = $2',
      v_ref.tabela, v_ref.coluna, v_ref.coluna)
      using p_fornecedor_destino_id, p_fornecedor_origem_id;
    get diagnostics v_movidos = row_count;
    if v_movidos > 0 then
      v_total_movidos := v_total_movidos + v_movidos;
      v_impacto := v_impacto || jsonb_build_object(
        v_ref.tabela::text || '.' || v_ref.coluna, v_movidos
      );
    end if;
  end loop;

  v_tipo := case
    when v_destino.tipo_entidade = 'ambos' or v_origem.tipo_entidade = 'ambos' then 'ambos'
    when v_destino.tipo_entidade in ('fornecedor', 'subempreiteiro')
     and v_origem.tipo_entidade in ('fornecedor', 'subempreiteiro')
     and v_destino.tipo_entidade <> v_origem.tipo_entidade then 'ambos'
    when v_destino.tipo_entidade in ('fornecedor', 'subempreiteiro') then v_destino.tipo_entidade
    else v_origem.tipo_entidade
  end;

  update public.fornecedores set
    nif = coalesce(nullif(nif, ''), nullif(v_origem.nif, '')),
    email = coalesce(nullif(email, ''), nullif(v_origem.email, '')),
    telefone = coalesce(nullif(telefone, ''), nullif(v_origem.telefone, '')),
    representante = coalesce(nullif(representante, ''), nullif(v_origem.representante, '')),
    notas = coalesce(nullif(notas, ''), nullif(v_origem.notas, '')),
    tipo_entidade = coalesce(nullif(v_tipo, ''), tipo_entidade),
    estado_confianca = case
      when coalesce(estado_confianca, 'nao_avaliado') = 'nao_avaliado'
       and coalesce(v_origem.estado_confianca, 'nao_avaliado') <> 'nao_avaliado'
      then v_origem.estado_confianca else estado_confianca end
  where id = p_fornecedor_destino_id;

  insert into public.fornecedores_mesclagens(
    empresa_id, fornecedor_origem_id, fornecedor_destino_id,
    nome_origem, nome_destino, impacto, executado_por
  ) values (
    v_atual.empresa_id, p_fornecedor_origem_id, p_fornecedor_destino_id,
    v_origem.nome, v_destino.nome,
    jsonb_build_object('total_movidos', v_total_movidos, 'tabelas', v_impacto),
    v_atual.id
  );

  delete from public.fornecedores where id = p_fornecedor_origem_id;

  return jsonb_build_object(
    'mesclado', true,
    'origem_id', p_fornecedor_origem_id,
    'destino_id', p_fornecedor_destino_id,
    'total_movidos', v_total_movidos,
    'impacto', v_impacto,
    'alias_preservado', v_origem.nome
  );
exception
  when unique_violation then
    raise exception 'A mesclagem foi cancelada sem alterar dados porque criaria um registo duplicado: %', sqlerrm;
end;
$function$;

revoke all on function public.fn_mesclar_fornecedor(uuid, uuid)
  from public, anon;
grant execute on function public.fn_mesclar_fornecedor(uuid, uuid)
  to authenticated;

alter table public.fornecedores_aliases enable row level security;
alter table public.fornecedores_mesclagens enable row level security;
revoke all on public.fornecedores_aliases, public.fornecedores_mesclagens from anon;
grant select on public.fornecedores_aliases, public.fornecedores_mesclagens to authenticated;

drop policy if exists fornecedores_aliases_empresa_select on public.fornecedores_aliases;
create policy fornecedores_aliases_empresa_select on public.fornecedores_aliases
for select to authenticated using (
  empresa_id = (select empresa_id from public.utilizadores where id = public.fn_utilizador_atual_id())
);

drop policy if exists fornecedores_mesclagens_empresa_select on public.fornecedores_mesclagens;
create policy fornecedores_mesclagens_empresa_select on public.fornecedores_mesclagens
for select to authenticated using (
  empresa_id = (select empresa_id from public.utilizadores where id = public.fn_utilizador_atual_id())
);

commit;

select
  to_regprocedure('public.fn_previsualizar_mesclagem_fornecedor(uuid,uuid)') is not null as previsualizacao_ativa,
  to_regprocedure('public.fn_mesclar_fornecedor(uuid,uuid)') is not null as mesclagem_ativa,
  to_regclass('public.fornecedores_aliases') is not null as aliases_ativos,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'faturas'
      and column_name = 'fornecedor_nome_original'
  ) as nome_original_fatura_ativo;
