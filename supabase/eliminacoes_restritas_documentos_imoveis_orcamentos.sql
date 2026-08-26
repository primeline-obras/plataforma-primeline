-- PRIMELINE | Eliminações restritas e cancelamento lógico
-- Documentos, imóveis e versões: apagar com permissão e auditoria.
-- Pedidos de orçamento: cancelamento lógico, preservando o histórico.

begin;

create or replace function public.fn_apagar_documento_obra(p_documento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
begin
  select obra_id into v_obra_id
  from public.documentos_obra
  where id = p_documento_id;

  if v_obra_id is null then
    raise exception 'Documento não encontrado.';
  end if;
  if not public.fn_pode_editar_documentos_obra(v_obra_id) then
    raise exception 'Sem permissão para apagar este documento.';
  end if;

  delete from public.documentos_obra where id = p_documento_id;
end;
$$;

create or replace function public.fn_apagar_documento_entidade(p_documento_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar documentos de entidades.';
  end if;
  if not exists (select 1 from public.documentos where id = p_documento_id) then
    raise exception 'Documento não encontrado.';
  end if;
  delete from public.documentos where id = p_documento_id;
end;
$$;

create or replace function public.fn_apagar_reuniao_condominio(p_reuniao_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar reuniões de condomínio.';
  end if;
  if not exists (select 1 from public.imoveis_reunioes_condominio where id = p_reuniao_id) then
    raise exception 'Reunião não encontrada.';
  end if;
  delete from public.imoveis_reunioes_condominio where id = p_reuniao_id;
end;
$$;

create or replace function public.fn_apagar_imovel_empresa(p_imovel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar imóveis.';
  end if;
  if not exists (select 1 from public.imoveis_empresa where id = p_imovel_id) then
    raise exception 'Imóvel não encontrado.';
  end if;

  delete from public.imoveis_reunioes_condominio where imovel_id = p_imovel_id;
  delete from public.imoveis_empresa where id = p_imovel_id;
end;
$$;

create or replace function public.fn_cancelar_pedido_orcamento(p_pedido_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode cancelar pedidos de orçamento.';
  end if;
  if not exists (select 1 from public.pedidos_orcamento where id = p_pedido_id) then
    raise exception 'Pedido de orçamento não encontrado.';
  end if;

  update public.pedidos_orcamento
  set estado = 'cancelado',
      situacao_atual = coalesce(nullif(btrim(situacao_atual), ''), 'Cancelado pelo utilizador')
  where id = p_pedido_id;
end;
$$;

create or replace function public.fn_apagar_versao_pedido_orcamento(p_versao_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar versões de pedidos de orçamento.';
  end if;
  if not exists (select 1 from public.pedidos_orcamento_versoes where id = p_versao_id) then
    raise exception 'Versão não encontrada.';
  end if;

  delete from public.pedidos_orcamento_versoes where id = p_versao_id;
end;
$$;

revoke all on function public.fn_apagar_documento_obra(uuid) from public, anon;
revoke all on function public.fn_apagar_documento_entidade(uuid) from public, anon;
revoke all on function public.fn_apagar_reuniao_condominio(uuid) from public, anon;
revoke all on function public.fn_apagar_imovel_empresa(uuid) from public, anon;
revoke all on function public.fn_cancelar_pedido_orcamento(uuid) from public, anon;
revoke all on function public.fn_apagar_versao_pedido_orcamento(uuid) from public, anon;
grant execute on function public.fn_apagar_documento_obra(uuid) to authenticated;
grant execute on function public.fn_apagar_documento_entidade(uuid) to authenticated;
grant execute on function public.fn_apagar_reuniao_condominio(uuid) to authenticated;
grant execute on function public.fn_apagar_imovel_empresa(uuid) to authenticated;
grant execute on function public.fn_cancelar_pedido_orcamento(uuid) to authenticated;
grant execute on function public.fn_apagar_versao_pedido_orcamento(uuid) to authenticated;

-- A remoção física no Storage só é permitida a quem pode editar a obra.
drop policy if exists documentos_obra_storage_delete on storage.objects;
create policy documentos_obra_storage_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.fn_pode_editar_documentos_obra(((storage.foldername(name))[1])::uuid)
);

drop policy if exists documentos_empresa_storage_delete on storage.objects;
create policy documentos_empresa_storage_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'empresa'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

-- Garante auditoria também nas tabelas criadas depois da ativação global.
do $$
declare
  v_tabela text;
begin
  foreach v_tabela in array array[
    'documentos_obra',
    'documentos',
    'imoveis_empresa',
    'imoveis_reunioes_condominio',
    'pedidos_orcamento',
    'pedidos_orcamento_versoes'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'trg_auditoria_' || v_tabela, v_tabela);
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function public.fn_registar_log_auditoria(''id'')',
      'trg_auditoria_' || v_tabela,
      v_tabela
    );
  end loop;
end;
$$;

commit;

select
  to_regprocedure('public.fn_apagar_documento_obra(uuid)') is not null as apagar_documento,
  to_regprocedure('public.fn_apagar_documento_entidade(uuid)') is not null as apagar_documento_entidade,
  to_regprocedure('public.fn_apagar_imovel_empresa(uuid)') is not null as apagar_imovel,
  to_regprocedure('public.fn_apagar_reuniao_condominio(uuid)') is not null as apagar_reuniao,
  to_regprocedure('public.fn_cancelar_pedido_orcamento(uuid)') is not null as cancelar_pedido,
  to_regprocedure('public.fn_apagar_versao_pedido_orcamento(uuid)') is not null as apagar_versao,
  (select count(*) from pg_trigger where tgname in (
    'trg_auditoria_documentos_obra',
    'trg_auditoria_documentos',
    'trg_auditoria_imoveis_empresa',
    'trg_auditoria_imoveis_reunioes_condominio',
    'trg_auditoria_pedidos_orcamento',
    'trg_auditoria_pedidos_orcamento_versoes'
  ) and not tgisinternal) as auditorias_ativas;
