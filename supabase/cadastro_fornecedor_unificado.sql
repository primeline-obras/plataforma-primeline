-- PRIMELINE GO | Gravação única do cadastro de fornecedores e subempreiteiros
-- Mantém dados, zonas e especialidades na mesma transação.
begin;

create or replace function public.fn_guardar_cadastro_fornecedor(
  p_fornecedor_id uuid,
  p_nome text,
  p_tipo_entidade text,
  p_nif text,
  p_email text,
  p_telefone text,
  p_representante text,
  p_notas text,
  p_estado_confianca text,
  p_zonas text[] default '{}'::text[],
  p_especialidades uuid[] default '{}'::uuid[],
  p_nova_especialidade text default null
)
returns public.fornecedores
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fornecedor public.fornecedores;
  v_fornecedor_id uuid := p_fornecedor_id;
  v_empresa_id uuid;
  v_nome_normalizado text := lower(regexp_replace(btrim(coalesce(p_nome, '')), '[[:space:]]+', ' ', 'g'));
  v_nif_normalizado text := nullif(regexp_replace(coalesce(p_nif, ''), '[^0-9A-Za-z]', '', 'g'), '');
  v_especialidades uuid[] := coalesce(p_especialidades, '{}'::uuid[]);
  v_especialidade_id uuid;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode editar o diretório.' using errcode = '42501';
  end if;

  if nullif(v_nome_normalizado, '') is null then
    raise exception 'O nome do fornecedor ou subempreiteiro é obrigatório.';
  end if;
  if p_tipo_entidade not in ('fornecedor', 'subempreiteiro', 'ambos') then
    raise exception 'Selecione Fornecedor, Subempreiteiro ou Fornecedor e Subempreiteiro.';
  end if;
  if p_estado_confianca not in (
    'ativo', 'recomendado', 'recomendado_com_ressalvas', 'nao_avaliado',
    'nao_recomendado', 'bloqueado', 'inativo'
  ) then
    raise exception 'O estado de confiança indicado não é válido.';
  end if;
  if nullif(btrim(p_email), '') is not null and position('@' in btrim(p_email)) < 2 then
    raise exception 'O email indicado não é válido.';
  end if;

  select u.empresa_id into v_empresa_id
  from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id()
    and coalesce(u.ativo, true);
  if v_empresa_id is null then
    raise exception 'Utilizador sem empresa ativa.' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_empresa_id::text), hashtext(v_nome_normalizado));

  if exists (
    select 1 from public.fornecedores f
    where f.empresa_id = v_empresa_id
      and (v_fornecedor_id is null or f.id <> v_fornecedor_id)
      and lower(regexp_replace(btrim(coalesce(f.nome, '')), '[[:space:]]+', ' ', 'g')) = v_nome_normalizado
  ) then
    raise exception 'Já existe um cadastro com este nome. Abra o registo existente para o rever ou completar.';
  end if;

  if v_nif_normalizado is not null and exists (
    select 1 from public.fornecedores f
    where f.empresa_id = v_empresa_id
      and (v_fornecedor_id is null or f.id <> v_fornecedor_id)
      and regexp_replace(coalesce(f.nif, ''), '[^0-9A-Za-z]', '', 'g') = v_nif_normalizado
  ) then
    raise exception 'Já existe um cadastro com este NIF. Abra o registo existente para o rever ou completar.';
  end if;

  if exists (
    select 1
    from unnest(v_especialidades) as selecionada(especialidade_id)
    left join public.especialidades e
      on e.id = selecionada.especialidade_id
    where e.id is null or not coalesce(e.aplicavel_subempreiteiro, false)
  ) then
    raise exception 'A seleção contém uma especialidade inválida.';
  end if;

  if v_fornecedor_id is null then
    begin
      insert into public.fornecedores (
        empresa_id, nome, tipo_entidade, nif, email, telefone,
        representante, notas, estado_confianca
      ) values (
        v_empresa_id, btrim(p_nome), p_tipo_entidade,
        nullif(btrim(p_nif), ''), nullif(lower(btrim(p_email)), ''),
        nullif(btrim(p_telefone), ''), nullif(btrim(p_representante), ''),
        nullif(btrim(p_notas), ''), p_estado_confianca
      ) returning * into v_fornecedor;
      v_fornecedor_id := v_fornecedor.id;
    exception when unique_violation then
      raise exception 'Já existe um cadastro com este nome ou NIF. Abra o registo existente para o rever ou completar.';
    end;
  else
    select * into v_fornecedor
    from public.fn_editar_fornecedor_diretorio_v2(
      v_fornecedor_id, p_nome, p_tipo_entidade, p_nif, p_email,
      p_telefone, p_representante, p_notas, p_estado_confianca
    );
  end if;

  perform public.fn_definir_zonas_fornecedor(
    v_fornecedor_id,
    coalesce(p_zonas, '{}'::text[])
  );

  delete from public.fornecedores_especialidades fe
  where fe.fornecedor_id = v_fornecedor_id
    and not (fe.especialidade_id = any(v_especialidades));

  foreach v_especialidade_id in array v_especialidades loop
    insert into public.fornecedores_especialidades (
      fornecedor_id, especialidade_id, origem, criado_por
    ) values (
      v_fornecedor_id, v_especialidade_id, 'manual', public.fn_utilizador_atual_id()
    ) on conflict (fornecedor_id, especialidade_id) do nothing;
  end loop;

  if nullif(btrim(p_nova_especialidade), '') is not null then
    perform public.fn_criar_especialidade_fornecedor(
      v_fornecedor_id,
      p_nova_especialidade
    );
  end if;

  select * into v_fornecedor
  from public.fornecedores f
  where f.id = v_fornecedor_id;

  return v_fornecedor;
end;
$function$;

revoke all on function public.fn_guardar_cadastro_fornecedor(
  uuid, text, text, text, text, text, text, text, text, text[], uuid[], text
) from public, anon;
grant execute on function public.fn_guardar_cadastro_fornecedor(
  uuid, text, text, text, text, text, text, text, text, text[], uuid[], text
) to authenticated;

commit;

select
  to_regprocedure(
    'public.fn_guardar_cadastro_fornecedor(uuid,text,text,text,text,text,text,text,text,text[],uuid[],text)'
  ) is not null as cadastro_unificado_ativo,
  pg_get_functiondef(
    to_regprocedure(
      'public.fn_guardar_cadastro_fornecedor(uuid,text,text,text,text,text,text,text,text,text[],uuid[],text)'
    )
  ) ilike '%v_fornecedor_id is null%' as criacao_fornecedor_ativa;
