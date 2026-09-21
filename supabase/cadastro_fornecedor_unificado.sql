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
  v_especialidades uuid[] := coalesce(p_especialidades, '{}'::uuid[]);
  v_especialidade_id uuid;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then
    raise exception 'Só o Administrativo ou a Gestão da Plataforma pode editar o diretório.' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(v_especialidades) id
    left join public.especialidades e on e.id = id
    where e.id is null or not coalesce(e.aplicavel_subempreiteiro, false)
  ) then
    raise exception 'A seleção contém uma especialidade inválida.';
  end if;

  select * into v_fornecedor
  from public.fn_editar_fornecedor_diretorio_v2(
    p_fornecedor_id, p_nome, p_tipo_entidade, p_nif, p_email,
    p_telefone, p_representante, p_notas, p_estado_confianca
  );

  perform public.fn_definir_zonas_fornecedor(
    p_fornecedor_id,
    coalesce(p_zonas, '{}'::text[])
  );

  delete from public.fornecedores_especialidades fe
  where fe.fornecedor_id = p_fornecedor_id
    and not (fe.especialidade_id = any(v_especialidades));

  foreach v_especialidade_id in array v_especialidades loop
    insert into public.fornecedores_especialidades (
      fornecedor_id, especialidade_id, origem, criado_por
    ) values (
      p_fornecedor_id, v_especialidade_id, 'manual', public.fn_utilizador_atual_id()
    ) on conflict (fornecedor_id, especialidade_id) do nothing;
  end loop;

  if nullif(btrim(p_nova_especialidade), '') is not null then
    perform public.fn_criar_especialidade_fornecedor(
      p_fornecedor_id,
      p_nova_especialidade
    );
  end if;

  select * into v_fornecedor
  from public.fornecedores
  where id = p_fornecedor_id;

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
  ) is not null as cadastro_unificado_ativo;
