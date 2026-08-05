-- PRIMELINE | Relatórios de Não Conformidade
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.rnc enable row level security;
alter table public.rnc_anexos enable row level security;

revoke all on table public.rnc, public.rnc_anexos from anon;
revoke insert, update, delete on table public.rnc from authenticated;
grant select on table public.rnc to authenticated;
grant select, insert on table public.rnc_anexos to authenticated;

create or replace function public.fn_proximo_numero_rnc(p_obra_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    public.fn_pode_ver_obra(p_obra_id)
    or public.fn_e_encarregado_da_obra(p_obra_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissão para consultar RNCs desta obra.';
  end if;

  return (
    select coalesce(max(numero), 0) + 1
    from public.rnc
    where obra_id = p_obra_id
  );
end;
$$;

create or replace function public.fn_criar_rnc(
  p_obra_id uuid,
  p_data_deteccao date,
  p_fase_id uuid,
  p_local_ocorrencia text,
  p_descricao text,
  p_origem text,
  p_subempreitada_id uuid,
  p_gravidade text
)
returns public.rnc
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_numero integer;
  v_rnc public.rnc;
begin
  if not (
    public.fn_pode_editar_obra(p_obra_id)
    or public.fn_e_encarregado_da_obra(p_obra_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissão para criar RNC nesta obra.';
  end if;

  if nullif(btrim(p_descricao), '') is null then
    raise exception using errcode = '23514', message = 'A descrição é obrigatória.';
  end if;

  if p_origem not in ('execucao_propria', 'subempreiteiro', 'material', 'projeto_especificacao', 'outro') then
    raise exception using errcode = '23514', message = 'Origem inválida.';
  end if;

  if p_gravidade not in ('critica', 'maior', 'menor') then
    raise exception using errcode = '23514', message = 'Gravidade inválida.';
  end if;

  if p_fase_id is not null and not exists (
    select 1 from public.fases f
    where f.id = p_fase_id and f.obra_id = p_obra_id
  ) then
    raise exception using errcode = '23503', message = 'A fase não pertence à obra indicada.';
  end if;

  if p_origem = 'subempreiteiro' then
    if p_subempreitada_id is null or not exists (
      select 1 from public.subempreitadas s
      where s.id = p_subempreitada_id and s.obra_id = p_obra_id
    ) then
      raise exception using errcode = '23503', message = 'Selecione uma subempreitada válida desta obra.';
    end if;
  else
    p_subempreitada_id := null;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('rnc:' || p_obra_id::text, 0));

  select coalesce(max(numero), 0) + 1 into v_numero
  from public.rnc
  where obra_id = p_obra_id;

  insert into public.rnc (
    obra_id, numero, fase_id, subempreitada_id, data_deteccao,
    local_ocorrencia, descricao, origem, gravidade, estado, reportado_por
  ) values (
    p_obra_id, v_numero, p_fase_id, p_subempreitada_id,
    coalesce(p_data_deteccao, current_date), nullif(btrim(p_local_ocorrencia), ''),
    btrim(p_descricao), p_origem, p_gravidade, 'aberto',
    public.fn_utilizador_atual_id()
  ) returning * into v_rnc;

  return v_rnc;
end;
$$;

create or replace function public.fn_definir_acao_rnc(
  p_rnc_id uuid,
  p_acao_corretiva text,
  p_responsavel_correcao text,
  p_prazo_correcao date
)
returns public.rnc
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rnc public.rnc;
begin
  select * into v_rnc from public.rnc where id = p_rnc_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'RNC não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_rnc.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para definir a ação corretiva.';
  end if;
  if v_rnc.estado in ('verificado', 'fechado') then
    raise exception using errcode = '23514', message = 'Esta RNC já não aceita uma nova ação corretiva.';
  end if;
  if nullif(btrim(p_acao_corretiva), '') is null
     or nullif(btrim(p_responsavel_correcao), '') is null
     or p_prazo_correcao is null then
    raise exception using errcode = '23514', message = 'Ação, responsável e prazo são obrigatórios.';
  end if;

  update public.rnc set
    acao_corretiva = btrim(p_acao_corretiva),
    responsavel_correcao = btrim(p_responsavel_correcao),
    prazo_correcao = p_prazo_correcao,
    estado = 'em_correcao'
  where id = p_rnc_id
  returning * into v_rnc;
  return v_rnc;
end;
$$;

drop function if exists public.fn_verificar_rnc(uuid);
create or replace function public.fn_verificar_rnc(
  p_rnc_id uuid,
  p_observacao_verificacao text default null
)
returns public.rnc
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rnc public.rnc;
begin
  select * into v_rnc from public.rnc where id = p_rnc_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'RNC não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_rnc.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para verificar esta RNC.';
  end if;
  if v_rnc.estado <> 'em_correcao' then
    raise exception using errcode = '23514', message = 'Só uma RNC em correção pode ser verificada.';
  end if;

  update public.rnc set
    observacao_verificacao = coalesce(nullif(btrim(p_observacao_verificacao), ''), observacao_verificacao),
    estado = 'verificado',
    verificado_por = public.fn_utilizador_atual_id()
  where id = p_rnc_id returning * into v_rnc;
  return v_rnc;
end;
$$;

create or replace function public.fn_fechar_rnc(p_rnc_id uuid)
returns public.rnc
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rnc public.rnc;
begin
  select * into v_rnc from public.rnc where id = p_rnc_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'RNC não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_rnc.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para fechar esta RNC.';
  end if;
  if v_rnc.estado <> 'verificado' then
    raise exception using errcode = '23514', message = 'Só uma RNC verificada pode ser fechada.';
  end if;

  update public.rnc set estado = 'fechado', data_fecho = current_date
  where id = p_rnc_id returning * into v_rnc;
  return v_rnc;
end;
$$;

revoke all on function public.fn_proximo_numero_rnc(uuid) from public, anon;
revoke all on function public.fn_criar_rnc(uuid, date, uuid, text, text, text, uuid, text) from public, anon;
revoke all on function public.fn_definir_acao_rnc(uuid, text, text, date) from public, anon;
revoke all on function public.fn_verificar_rnc(uuid, text) from public, anon;
revoke all on function public.fn_fechar_rnc(uuid) from public, anon;
grant execute on function public.fn_proximo_numero_rnc(uuid) to authenticated;
grant execute on function public.fn_criar_rnc(uuid, date, uuid, text, text, text, uuid, text) to authenticated;
grant execute on function public.fn_definir_acao_rnc(uuid, text, text, date) to authenticated;
grant execute on function public.fn_verificar_rnc(uuid, text) to authenticated;
grant execute on function public.fn_fechar_rnc(uuid) to authenticated;

alter table public.avaliacoes_subempreiteiro_anexos enable row level security;
alter table public.faturas_anexos enable row level security;
revoke all on table public.avaliacoes_subempreiteiro_anexos, public.faturas_anexos from anon;
grant select, insert on table public.avaliacoes_subempreiteiro_anexos, public.faturas_anexos to authenticated;

drop policy if exists avaliacoes_subempreiteiro_anexos_select on public.avaliacoes_subempreiteiro_anexos;
create policy avaliacoes_subempreiteiro_anexos_select
on public.avaliacoes_subempreiteiro_anexos for select to authenticated
using (exists (
  select 1 from public.avaliacoes_subempreiteiro a
  where a.id = avaliacoes_subempreiteiro_anexos.avaliacao_id
    and public.fn_pode_ver_obra(a.obra_id)
));

drop policy if exists avaliacoes_subempreiteiro_anexos_insert on public.avaliacoes_subempreiteiro_anexos;
create policy avaliacoes_subempreiteiro_anexos_insert
on public.avaliacoes_subempreiteiro_anexos for insert to authenticated
with check (exists (
  select 1 from public.avaliacoes_subempreiteiro a
  where a.id = avaliacoes_subempreiteiro_anexos.avaliacao_id
    and public.fn_pode_editar_obra(a.obra_id)
));

drop policy if exists faturas_anexos_select on public.faturas_anexos;
create policy faturas_anexos_select
on public.faturas_anexos for select to authenticated
using (exists (
  select 1 from public.faturas f
  where f.id = faturas_anexos.fatura_id and public.fn_pode_ver_obra(f.obra_id)
));

drop policy if exists faturas_anexos_insert on public.faturas_anexos;
create policy faturas_anexos_insert
on public.faturas_anexos for insert to authenticated
with check (exists (
  select 1 from public.faturas f
  where f.id = faturas_anexos.fatura_id and public.fn_pode_editar_obra(f.obra_id)
));

drop policy if exists rnc_storage_insert on storage.objects;
create policy rnc_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (storage.foldername(name))[2] = 'rnc'
  and (
    public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid)
  )
);

drop policy if exists avaliacoes_storage_insert on storage.objects;
create policy avaliacoes_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = 'avaliacoes-subempreiteiro'
  and public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
);

drop policy if exists faturas_anexos_storage_insert on storage.objects;
create policy faturas_anexos_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'faturas'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = 'faturas-anexos'
  and public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
);

drop policy if exists documentos_storage_select on storage.objects;
create policy documentos_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
    or (
      public.fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid)
      and (storage.foldername(name))[2] in (
        'articulado_original', 'articulado_tee', 'desenho',
        'desenhos_preparacao', 'plantas_projeto', 'pdes_rfis',
        'pames', 'atas_reuniao', 'rnc'
      )
    )
  )
);

commit;
