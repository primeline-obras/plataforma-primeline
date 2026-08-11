-- PRIMELINE | Ações do Financeiro e rastreio completo da fatura
begin;

alter table public.faturas
  add column if not exists observacao_devolucao text,
  add column if not exists devolvido_por uuid references public.utilizadores(id),
  add column if not exists devolvido_em timestamptz;

create table if not exists public.faturas_eventos (
  id uuid primary key default gen_random_uuid(),
  fatura_id uuid not null references public.faturas(id) on delete cascade,
  tipo text not null check (tipo in ('paga', 'pagamento_revertido', 'devolvida', 'anexo_adicionado')),
  observacao text,
  utilizador_id uuid references public.utilizadores(id),
  criado_em timestamptz not null default now()
);

create index if not exists faturas_eventos_fatura_data_idx
  on public.faturas_eventos (fatura_id, criado_em desc);

alter table public.faturas_eventos enable row level security;
revoke all on table public.faturas_eventos from anon, authenticated;

create or replace function public.fn_registar_evento_financeiro_fatura()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if tg_table_name = 'faturas_anexos' and tg_op = 'INSERT' then
    insert into public.faturas_eventos (fatura_id, tipo, observacao, utilizador_id)
    values (new.fatura_id, 'anexo_adicionado', new.nome_arquivo, public.fn_utilizador_atual_id());
    return new;
  end if;

  if old.estado_pagamento is distinct from new.estado_pagamento then
    if new.estado_pagamento = 'pago' then
      insert into public.faturas_eventos (fatura_id, tipo, utilizador_id)
      values (new.id, 'paga', public.fn_utilizador_atual_id());
    elsif old.estado_pagamento = 'pago' and new.estado_pagamento = 'por_pagar' then
      insert into public.faturas_eventos (fatura_id, tipo, utilizador_id)
      values (new.id, 'pagamento_revertido', public.fn_utilizador_atual_id());
    end if;
  end if;

  if old.estado_aprovacao = 'aprovado'
     and new.estado_aprovacao = 'pendente'
     and nullif(btrim(new.observacao_devolucao), '') is not null then
    insert into public.faturas_eventos (fatura_id, tipo, observacao, utilizador_id)
    values (new.id, 'devolvida', new.observacao_devolucao, public.fn_utilizador_atual_id());
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_registar_evento_financeiro_fatura() from public, anon, authenticated;

drop trigger if exists trg_eventos_financeiros_fatura on public.faturas;
create trigger trg_eventos_financeiros_fatura
after update of estado_aprovacao, estado_pagamento on public.faturas
for each row execute function public.fn_registar_evento_financeiro_fatura();

drop trigger if exists trg_evento_anexo_fatura on public.faturas_anexos;
create trigger trg_evento_anexo_fatura
after insert on public.faturas_anexos
for each row execute function public.fn_registar_evento_financeiro_fatura();

create or replace function public.fn_desmarcar_fatura_paga(p_fatura_id uuid)
returns public.faturas
language plpgsql
security definer
set search_path = public
as $function$
declare v_fatura public.faturas;
begin
  if not public.fn_e_financeiro() then
    raise exception 'A reversão do pagamento está reservada ao papel Financeiro.';
  end if;
  select * into v_fatura from public.faturas where id = p_fatura_id for update;
  if not found or v_fatura.estado_aprovacao <> 'aprovado' or v_fatura.estado_pagamento <> 'pago' then
    raise exception 'Esta fatura não está marcada como paga.';
  end if;
  update public.faturas
  set estado_pagamento = 'por_pagar', data_pagamento = null, pago_por = null
  where id = p_fatura_id returning * into v_fatura;
  return v_fatura;
end;
$function$;

create or replace function public.fn_devolver_fatura_financeiro(p_fatura_id uuid, p_observacao text)
returns public.faturas
language plpgsql
security definer
set search_path = public
as $function$
declare v_fatura public.faturas;
begin
  if not public.fn_e_financeiro() then
    raise exception 'A devolução está reservada ao papel Financeiro.';
  end if;
  if nullif(btrim(p_observacao), '') is null then
    raise exception 'A observação é obrigatória para devolver a fatura.';
  end if;
  select * into v_fatura from public.faturas where id = p_fatura_id for update;
  if not found or v_fatura.estado_aprovacao <> 'aprovado' or v_fatura.estado_pagamento <> 'por_pagar' then
    raise exception 'Só pode devolver uma fatura aprovada que ainda não foi paga.';
  end if;
  update public.faturas
  set estado_aprovacao = 'pendente',
      observacao_devolucao = btrim(p_observacao),
      devolvido_por = public.fn_utilizador_atual_id(),
      devolvido_em = now(),
      aprovado_por = null,
      data_aprovacao = null
  where id = p_fatura_id returning * into v_fatura;
  return v_fatura;
end;
$function$;

revoke all on function public.fn_desmarcar_fatura_paga(uuid) from public, anon;
revoke all on function public.fn_devolver_fatura_financeiro(uuid, text) from public, anon;
grant execute on function public.fn_desmarcar_fatura_paga(uuid) to authenticated;
grant execute on function public.fn_devolver_fatura_financeiro(uuid, text) to authenticated;

drop policy if exists faturas_anexos_select on public.faturas_anexos;
create policy faturas_anexos_select on public.faturas_anexos for select to authenticated
using (exists (
  select 1 from public.faturas f
  where f.id = faturas_anexos.fatura_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists faturas_anexos_insert on public.faturas_anexos;
create policy faturas_anexos_insert on public.faturas_anexos for insert to authenticated
with check (exists (
  select 1 from public.faturas f
  where f.id = faturas_anexos.fatura_id
    and (public.fn_pode_editar_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists faturas_anexos_storage_insert on storage.objects;
create policy faturas_anexos_storage_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'faturas'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = 'faturas-anexos'
  and (
    public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_financeiro()
  )
);

drop function if exists public.fn_listar_rastreio_faturas();
create function public.fn_listar_rastreio_faturas()
returns table (
  id uuid, obra_id uuid, obra_numero text, obra_nome text, fornecedor_nome text,
  numero_doc text, valor numeric, estado_aprovacao text, estado_pagamento text,
  criado_em timestamptz, criado_por uuid, criado_por_nome text,
  data_aprovacao timestamptz, aprovado_por uuid, aprovado_por_nome text,
  data_pagamento date, pago_por uuid, pago_por_nome text, eventos jsonb
)
language sql stable security definer set search_path = public
as $function$
  select f.id, f.obra_id, o.numero::text, o.nome, fr.nome, f.numero_doc, f.valor,
    f.estado_aprovacao, f.estado_pagamento, f.criado_em, f.criado_por, uc.nome,
    f.data_aprovacao, f.aprovado_por, ua.nome, f.data_pagamento, f.pago_por, up.nome,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo', e.tipo, 'observacao', e.observacao, 'criado_em', e.criado_em,
        'utilizador_id', e.utilizador_id, 'utilizador_nome', ue.nome
      ) order by e.criado_em)
      from public.faturas_eventos e
      left join public.utilizadores ue on ue.id = e.utilizador_id
      where e.fatura_id = f.id
    ), '[]'::jsonb)
  from public.faturas f
  join public.obras o on o.id = f.obra_id
  left join public.fornecedores fr on fr.id = f.fornecedor_id
  left join public.utilizadores uc on uc.id = f.criado_por
  left join public.utilizadores ua on ua.id = f.aprovado_por
  left join public.utilizadores up on up.id = f.pago_por
  where public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()
     or public.fn_pode_ver_obra(f.obra_id)
  order by f.criado_em desc, f.id;
$function$;

revoke all on function public.fn_listar_rastreio_faturas() from public, anon;
grant execute on function public.fn_listar_rastreio_faturas() to authenticated;

drop trigger if exists trg_auditoria_faturas_eventos on public.faturas_eventos;
create trigger trg_auditoria_faturas_eventos
after insert or update or delete on public.faturas_eventos
for each row execute function public.fn_registar_log_auditoria('id');

commit;

select
  to_regprocedure('public.fn_desmarcar_fatura_paga(uuid)') is not null as rpc_desmarcar_paga,
  to_regprocedure('public.fn_devolver_fatura_financeiro(uuid,text)') is not null as rpc_devolver,
  to_regprocedure('public.fn_listar_rastreio_faturas()') is not null as rastreio_com_eventos,
  count(*) filter (where tgname in ('trg_eventos_financeiros_fatura','trg_evento_anexo_fatura')) as triggers_eventos
from pg_trigger where not tgisinternal;
