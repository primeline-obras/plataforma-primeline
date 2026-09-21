-- PRIMELINE GO | Classificação do diretório e especialidades manuais
-- Não classifica empresas existentes automaticamente.
begin;

do $block$
declare
  v_invalidos text;
  v_constraint record;
begin
  select string_agg(distinct coalesce(tipo_entidade, '<nulo>'), ', ' order by coalesce(tipo_entidade, '<nulo>'))
    into v_invalidos
  from public.fornecedores
  where tipo_entidade is not null
    and tipo_entidade not in ('fornecedor', 'fornecedor_material', 'subempreiteiro', 'ambos');
  if v_invalidos is not null then
    raise exception 'Existem tipos de parceiro desconhecidos: %. A migração não alterou esses dados.', v_invalidos;
  end if;

  select string_agg(distinct coalesce(estado_confianca, '<nulo>'), ', ' order by coalesce(estado_confianca, '<nulo>'))
    into v_invalidos
  from public.fornecedores
  where estado_confianca is not null
    and estado_confianca not in (
      'ativo', 'recomendado', 'recomendado_com_ressalvas', 'nao_avaliado',
      'nao_recomendado', 'bloqueado', 'inativo'
    );
  if v_invalidos is not null then
    raise exception 'Existem estados de confiança desconhecidos: %. A migração não alterou esses dados.', v_invalidos;
  end if;

  for v_constraint in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.fornecedores'::regclass
      and c.contype = 'c'
      and (
        pg_get_constraintdef(c.oid) ilike '%tipo_entidade%'
        or pg_get_constraintdef(c.oid) ilike '%estado_confianca%'
      )
  loop
    execute format('alter table public.fornecedores drop constraint %I', v_constraint.conname);
  end loop;
end;
$block$;

-- Nome legado usado pelo diretório atual: é semanticamente o mesmo que
-- "fornecedor" e pode ser normalizado sem perder informação.
update public.fornecedores
set tipo_entidade = 'fornecedor'
where tipo_entidade = 'fornecedor_material';

alter table public.fornecedores
  add constraint fornecedores_tipo_entidade_check
    check (tipo_entidade is null or tipo_entidade in ('fornecedor', 'subempreiteiro', 'ambos')),
  add constraint fornecedores_estado_confianca_check
    check (estado_confianca is null or estado_confianca in (
      'ativo', 'recomendado', 'recomendado_com_ressalvas', 'nao_avaliado',
      'nao_recomendado', 'bloqueado', 'inativo'
    ));

create or replace function public.fn_editar_fornecedor_diretorio_v2(
  p_fornecedor_id uuid,
  p_nome text,
  p_tipo_entidade text,
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
begin
  if p_tipo_entidade not in ('fornecedor', 'subempreiteiro', 'ambos') then
    raise exception 'Selecione Fornecedor, Subempreiteiro ou Fornecedor e Subempreiteiro.';
  end if;
  if p_estado_confianca not in (
    'ativo', 'recomendado', 'recomendado_com_ressalvas', 'nao_avaliado',
    'nao_recomendado', 'bloqueado', 'inativo'
  ) then
    raise exception 'O estado de confiança indicado não é válido.';
  end if;

  select * into v_fornecedor
  from public.fn_editar_fornecedor_diretorio(
    p_fornecedor_id, p_nome, p_nif, p_email, p_telefone,
    p_representante, p_notas, p_estado_confianca
  );

  update public.fornecedores
  set tipo_entidade = p_tipo_entidade
  where id = p_fornecedor_id
  returning * into v_fornecedor;

  return v_fornecedor;
end;
$function$;

revoke all on function public.fn_editar_fornecedor_diretorio_v2(
  uuid, text, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.fn_editar_fornecedor_diretorio_v2(
  uuid, text, text, text, text, text, text, text, text
) to authenticated;

create or replace function public.fn_criar_especialidade_fornecedor(
  p_fornecedor_id uuid,
  p_nome text
)
returns public.especialidades
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_especialidade public.especialidades;
  v_nome text := nullif(btrim(p_nome), '');
  v_nome_normalizado text;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode criar especialidades.' using errcode = '42501';
  end if;
  if v_nome is null or length(v_nome) < 3 then
    raise exception 'Indique uma especialidade com pelo menos 3 caracteres.';
  end if;
  if length(v_nome) > 120 then
    raise exception 'A especialidade não pode exceder 120 caracteres.';
  end if;
  if not exists (
    select 1
    from public.fornecedores f
    join public.utilizadores u on u.id = public.fn_utilizador_atual_id()
    where f.id = p_fornecedor_id
      and f.empresa_id = u.empresa_id
      and coalesce(u.ativo, true)
  ) then
    raise exception 'Fornecedor inexistente ou fora da sua empresa.';
  end if;

  v_nome_normalizado := regexp_replace(
    translate(lower(v_nome), 'áàãâäéèêëíìîïóòõôöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
    '[^a-z0-9]', '', 'g'
  );
  perform pg_advisory_xact_lock(hashtext('especialidade:' || v_nome_normalizado));

  select e.* into v_especialidade
  from public.especialidades e
  where regexp_replace(
    translate(lower(btrim(e.nome)), 'áàãâäéèêëíìîïóòõôöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
    '[^a-z0-9]', '', 'g'
  ) = v_nome_normalizado
  order by e.id
  limit 1
  for update;

  if not found then
    insert into public.especialidades (nome, aplicavel_subempreiteiro)
    values (v_nome, true)
    returning * into v_especialidade;
  elsif not coalesce(v_especialidade.aplicavel_subempreiteiro, false) then
    update public.especialidades
    set aplicavel_subempreiteiro = true
    where id = v_especialidade.id
    returning * into v_especialidade;
  end if;

  insert into public.fornecedores_especialidades (
    fornecedor_id, especialidade_id, origem, criado_por
  ) values (
    p_fornecedor_id, v_especialidade.id, 'manual', public.fn_utilizador_atual_id()
  ) on conflict (fornecedor_id, especialidade_id) do nothing;

  return v_especialidade;
end;
$function$;

revoke all on function public.fn_criar_especialidade_fornecedor(uuid, text)
from public, anon;
grant execute on function public.fn_criar_especialidade_fornecedor(uuid, text)
to authenticated;

create or replace function public.fn_eliminar_fornecedor_duplicado(
  p_fornecedor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fornecedor public.fornecedores;
  v_referencia record;
  v_total bigint;
  v_bloqueios text[] := array[]::text[];
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode eliminar registos duplicados.' using errcode = '42501';
  end if;

  select f.* into v_fornecedor
  from public.fornecedores f
  join public.utilizadores u on u.id = public.fn_utilizador_atual_id()
  where f.id = p_fornecedor_id
    and f.empresa_id = u.empresa_id
    and coalesce(u.ativo, true)
  for update;
  if not found then
    raise exception 'Fornecedor inexistente ou fora da sua empresa.';
  end if;

  -- Qualquer referência de negócio bloqueia a eliminação. Apenas as tabelas de
  -- classificação do próprio diretório podem ser limpas com o duplicado.
  for v_referencia in
    select
      c.conrelid::regclass as tabela,
      a.attname as coluna
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid
     and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid = 'public.fornecedores'::regclass
      and array_length(c.conkey, 1) = 1
      and c.conrelid not in (
        'public.fornecedores_zonas'::regclass,
        'public.fornecedores_especialidades'::regclass
      )
  loop
    execute format(
      'select count(*) from %s where %I = $1',
      v_referencia.tabela,
      v_referencia.coluna
    ) into v_total using p_fornecedor_id;
    if v_total > 0 then
      v_bloqueios := array_append(
        v_bloqueios,
        format('%s (%s registo%s)', v_referencia.tabela, v_total, case when v_total = 1 then '' else 's' end)
      );
    end if;
  end loop;

  if cardinality(v_bloqueios) > 0 then
    raise exception 'Este registo não pode ser eliminado porque já tem histórico associado: %. Consolide-o com o registo correto antes de eliminar.',
      array_to_string(v_bloqueios, ', ');
  end if;

  delete from public.fornecedores_zonas where fornecedor_id = p_fornecedor_id;
  delete from public.fornecedores_especialidades where fornecedor_id = p_fornecedor_id;
  delete from public.fornecedores where id = p_fornecedor_id;

  return jsonb_build_object(
    'eliminado', true,
    'fornecedor_id', p_fornecedor_id,
    'nome', v_fornecedor.nome
  );
end;
$function$;

revoke all on function public.fn_eliminar_fornecedor_duplicado(uuid)
from public, anon;
grant execute on function public.fn_eliminar_fornecedor_duplicado(uuid)
to authenticated;

commit;

select
  to_regprocedure('public.fn_editar_fornecedor_diretorio_v2(uuid,text,text,text,text,text,text,text,text)') is not null as edicao_com_tipo_ativa,
  to_regprocedure('public.fn_criar_especialidade_fornecedor(uuid,text)') is not null as especialidade_manual_ativa,
  to_regprocedure('public.fn_eliminar_fornecedor_duplicado(uuid)') is not null as eliminacao_duplicado_ativa,
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.fornecedores'::regclass
      and conname = 'fornecedores_estado_confianca_check'
  ) as avaliacao_intermedia_ativa;
