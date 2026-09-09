-- PRIMELINE GO | Eliminar um Mapa Comparativo completo
-- Executar depois de mapa_comparativo_editar_eliminar.sql.

begin;

create or replace function public.fn_eliminar_mapa_comparativo(p_mapa_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_obra_id uuid;
  v_item_ids uuid[];
  v_proposta_ids uuid[];
  v_itens_antes integer;
  v_propostas_antes integer;
  v_precos_antes integer;
  v_ajustes_antes integer;
  v_mapas_depois integer;
  v_itens_depois integer;
  v_propostas_depois integer;
  v_precos_depois integer;
  v_ajustes_depois integer;
begin
  select obra_id into v_obra_id
  from public.mapas_comparativos
  where id = p_mapa_id
  for update;

  if not found then
    raise exception 'Mapa comparativo não encontrado.' using errcode = 'P0002';
  end if;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar este mapa comparativo.' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.subempreitadas where mapa_comparativo_id = p_mapa_id
  ) then
    raise exception 'Este mapa já originou uma subempreitada e não pode ser eliminado. O histórico da adjudicação deve ser preservado.' using errcode = '23503';
  end if;

  select coalesce(array_agg(id), '{}'::uuid[]), count(*)
  into v_item_ids, v_itens_antes
  from public.comparativo_itens where mapa_id = p_mapa_id;

  select coalesce(array_agg(id), '{}'::uuid[]), count(*)
  into v_proposta_ids, v_propostas_antes
  from public.comparativo_propostas where mapa_id = p_mapa_id;

  select count(*) into v_precos_antes
  from public.comparativo_itens_precos
  where item_id = any(v_item_ids) or proposta_id = any(v_proposta_ids);

  select count(*) into v_ajustes_antes
  from public.comparativo_ajustes where mapa_id = p_mapa_id;

  delete from public.mapas_comparativos where id = p_mapa_id;

  select count(*) into v_mapas_depois from public.mapas_comparativos where id = p_mapa_id;
  select count(*) into v_itens_depois from public.comparativo_itens where id = any(v_item_ids);
  select count(*) into v_propostas_depois from public.comparativo_propostas where id = any(v_proposta_ids);
  select count(*) into v_precos_depois
  from public.comparativo_itens_precos
  where item_id = any(v_item_ids) or proposta_id = any(v_proposta_ids);
  select count(*) into v_ajustes_depois
  from public.comparativo_ajustes where mapa_id = p_mapa_id or proposta_id = any(v_proposta_ids);

  if v_mapas_depois <> 0 or v_itens_depois <> 0 or v_propostas_depois <> 0
     or v_precos_depois <> 0 or v_ajustes_depois <> 0 then
    raise exception 'A eliminação foi cancelada: existem registos relacionados com o mapa.';
  end if;

  return jsonb_build_object(
    'mapa_id', p_mapa_id,
    'itens_eliminados', v_itens_antes,
    'propostas_eliminadas', v_propostas_antes,
    'precos_eliminados', v_precos_antes,
    'ajustes_eliminados', v_ajustes_antes,
    'mapas_restantes', v_mapas_depois,
    'itens_restantes', v_itens_depois,
    'propostas_restantes', v_propostas_depois,
    'precos_restantes', v_precos_depois,
    'ajustes_restantes', v_ajustes_depois
  );
end;
$$;

revoke all on function public.fn_eliminar_mapa_comparativo(uuid) from public, anon;
grant execute on function public.fn_eliminar_mapa_comparativo(uuid) to authenticated;

commit;

select
  to_regprocedure('public.fn_eliminar_mapa_comparativo(uuid)') is not null as eliminar_mapa_disponivel,
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.mapas_comparativos'::regclass
      and tgname = 'trg_auditoria_mapas_comparativos'
      and not tgisinternal
  ) as auditoria_ativa;
