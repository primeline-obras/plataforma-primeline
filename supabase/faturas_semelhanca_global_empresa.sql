-- Verificação global de duplicados dentro da empresa, independentemente da obra.
begin;

create or replace function public.fn_verificar_fatura_semelhante(
  p_fornecedor_id uuid,
  p_valor numeric,
  p_numero_doc text,
  p_excluir_fatura_id uuid default null
)
returns table (
  id uuid,
  obra_id uuid,
  obra_numero text,
  numero_doc text,
  valor numeric,
  data_fatura date,
  estado_aprovacao text,
  estado_pagamento text,
  tipo_correspondencia text
)
language plpgsql
security definer
set search_path = public
stable
as $function$
declare
  v_atual public.utilizadores;
  v_tolerancia numeric;
begin
  select * into v_atual
  from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id()
    and coalesce(u.ativo, true);

  if not found then
    raise exception 'Utilizador autenticado sem perfil ativo.';
  end if;

  if p_fornecedor_id is null or p_valor is null or p_valor < 0 then
    raise exception 'Fornecedor e valor são obrigatórios para verificar duplicados.';
  end if;

  v_tolerancia := greatest(1.00, abs(p_valor) * 0.005);

  return query
  select
    f.id,
    f.obra_id,
    o.numero::text,
    f.numero_doc,
    f.valor,
    f.data_fatura,
    f.estado_aprovacao,
    f.estado_pagamento,
    case
      when lower(btrim(f.numero_doc)) = lower(btrim(coalesce(p_numero_doc, '')))
        then 'exata'::text
      else 'semelhante'::text
    end
  from public.faturas f
  join public.obras o on o.id = f.obra_id
  where o.empresa_id = v_atual.empresa_id
    and f.fornecedor_id = p_fornecedor_id
    and f.id is distinct from p_excluir_fatura_id
    and (
      lower(btrim(f.numero_doc)) = lower(btrim(coalesce(p_numero_doc, '')))
      or abs(f.valor - p_valor) <= v_tolerancia
    )
  order by
    case when lower(btrim(f.numero_doc)) = lower(btrim(coalesce(p_numero_doc, ''))) then 0 else 1 end,
    abs(f.valor - p_valor),
    f.data_fatura desc,
    f.criado_em desc
  limit 1;
end;
$function$;

revoke all on function public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid) from public, anon;
grant execute on function public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid) to authenticated;

-- O bloqueio exato também passa a ignorar a RLS durante a verificação.
create or replace function public.fn_bloquear_fatura_duplicada()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if public.fn_e_admin() then
    return new;
  end if;

  if exists (
    select 1
    from public.faturas f
    where f.fornecedor_id = new.fornecedor_id
      and lower(btrim(f.numero_doc)) = lower(btrim(new.numero_doc))
      and f.id is distinct from new.id
  ) then
    raise exception 'Já existe uma fatura com este número para este fornecedor — possível duplicação.';
  end if;

  return new;
end;
$function$;

revoke all on function public.fn_bloquear_fatura_duplicada() from public, anon, authenticated;

commit;

select
  to_regprocedure('public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid)') is not null
    as rpc_semelhanca_global,
  position(
    'security definer'
    in lower(pg_get_functiondef('public.fn_bloquear_fatura_duplicada()'::regprocedure))
  ) > 0 as bloqueio_exato_global;
