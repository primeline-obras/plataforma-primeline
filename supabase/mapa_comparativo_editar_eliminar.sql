-- PRIMELINE GO | Editar e eliminar itens/propostas do Mapa Comparativo
-- Executar no SQL Editor depois de mapa_comparativo_dinamico.sql.

begin;

-- As funções fazem a eliminação dentro de uma única transação, validam a
-- permissão da obra e confirmam que a cascata não deixou filhos órfãos.
create or replace function public.fn_eliminar_item_comparativo(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mapa_id uuid;
  v_obra_id uuid;
  v_precos_antes integer;
  v_precos_depois integer;
begin
  select i.mapa_id, m.obra_id into v_mapa_id, v_obra_id
  from public.comparativo_itens i
  join public.mapas_comparativos m on m.id = i.mapa_id
  where i.id = p_item_id
  for update of i;

  if not found then
    raise exception 'Item do mapa comparativo não encontrado.' using errcode = 'P0002';
  end if;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar itens desta obra.' using errcode = '42501';
  end if;

  select count(*) into v_precos_antes
  from public.comparativo_itens_precos where item_id = p_item_id;

  delete from public.comparativo_itens where id = p_item_id;

  select count(*) into v_precos_depois
  from public.comparativo_itens_precos where item_id = p_item_id;
  if v_precos_depois <> 0 then
    raise exception 'A eliminação foi cancelada: existem preços órfãos para o item.';
  end if;

  perform public.fn_atualizar_melhor_preco_comparativo(v_mapa_id);
  return jsonb_build_object(
    'item_id', p_item_id,
    'precos_eliminados', v_precos_antes,
    'precos_restantes', v_precos_depois
  );
end;
$$;

create or replace function public.fn_eliminar_proposta_comparativo(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mapa_id uuid;
  v_obra_id uuid;
  v_precos_antes integer;
  v_ajustes_antes integer;
  v_precos_depois integer;
  v_ajustes_depois integer;
begin
  select p.mapa_id, m.obra_id into v_mapa_id, v_obra_id
  from public.comparativo_propostas p
  join public.mapas_comparativos m on m.id = p.mapa_id
  where p.id = p_proposta_id
  for update of p;

  if not found then
    raise exception 'Proposta do mapa comparativo não encontrada.' using errcode = 'P0002';
  end if;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para eliminar propostas desta obra.' using errcode = '42501';
  end if;

  select count(*) into v_precos_antes
  from public.comparativo_itens_precos where proposta_id = p_proposta_id;
  select count(*) into v_ajustes_antes
  from public.comparativo_ajustes where proposta_id = p_proposta_id;

  delete from public.comparativo_propostas where id = p_proposta_id;

  select count(*) into v_precos_depois
  from public.comparativo_itens_precos where proposta_id = p_proposta_id;
  select count(*) into v_ajustes_depois
  from public.comparativo_ajustes where proposta_id = p_proposta_id;
  if v_precos_depois <> 0 or v_ajustes_depois <> 0 then
    raise exception 'A eliminação foi cancelada: existem preços ou ajustes órfãos para a proposta.';
  end if;

  perform public.fn_atualizar_melhor_preco_comparativo(v_mapa_id);
  return jsonb_build_object(
    'proposta_id', p_proposta_id,
    'precos_eliminados', v_precos_antes,
    'ajustes_eliminados', v_ajustes_antes,
    'precos_restantes', v_precos_depois,
    'ajustes_restantes', v_ajustes_depois
  );
end;
$$;

revoke all on function public.fn_eliminar_item_comparativo(uuid) from public, anon;
revoke all on function public.fn_eliminar_proposta_comparativo(uuid) from public, anon;
grant execute on function public.fn_eliminar_item_comparativo(uuid) to authenticated;
grant execute on function public.fn_eliminar_proposta_comparativo(uuid) to authenticated;

-- Regra geral da plataforma: eliminação restrita e registada em auditoria.
do $$
declare
  v_tabela text;
begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    foreach v_tabela in array array[
      'mapas_comparativos', 'comparativo_propostas', 'comparativo_itens',
      'comparativo_itens_precos', 'comparativo_ajustes'
    ] loop
      execute format('drop trigger if exists %I on public.%I', 'trg_auditoria_' || v_tabela, v_tabela);
      execute format(
        'create trigger %I after insert or update or delete on public.%I for each row execute function public.fn_registar_log_auditoria(''id'')',
        'trg_auditoria_' || v_tabela,
        v_tabela
      );
    end loop;
  end if;
end;
$$;

commit;

-- Confirma que as três relações críticas estão configuradas com CASCADE.
select
  con.conname as restricao,
  rel.relname as tabela,
  ref.relname as tabela_referenciada,
  case con.confdeltype when 'c' then 'CASCADE' else con.confdeltype::text end as ao_eliminar
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_class ref on ref.oid = con.confrelid
where con.contype = 'f'
  and (
    (rel.relname = 'comparativo_itens_precos' and ref.relname in ('comparativo_itens', 'comparativo_propostas'))
    or (rel.relname = 'comparativo_ajustes' and ref.relname = 'comparativo_propostas')
  )
order by rel.relname, ref.relname;

