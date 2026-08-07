-- PRIMELINE | Bloco 8 - exceção gerida ao bloqueio de faturas duplicadas.
-- Esta função já foi aplicada diretamente na base; a migração sincroniza o repositório.

create or replace function public.fn_bloquear_fatura_duplicada()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  if public.fn_e_admin() then
    -- Apenas Gerência/administradores da plataforma podem forçar uma
    -- duplicação genuína, depois da confirmação explícita no frontend.
    return new;
  end if;

  if exists (
    select 1
    from public.faturas f
    where f.fornecedor_id = new.fornecedor_id
      and f.numero_doc = new.numero_doc
      and f.id is distinct from new.id
  ) then
    raise exception
      'Já existe uma fatura com este número para este fornecedor — possível duplicação.';
  end if;

  return new;
end;
$function$;

revoke all
on function public.fn_bloquear_fatura_duplicada()
from public, anon, authenticated;

select
  to_regprocedure(
    'public.fn_bloquear_fatura_duplicada()'
  ) is not null as funcao_bloqueio,
  exists (
    select 1
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'public'
      and c.relname = 'faturas'
      and p.proname = 'fn_bloquear_fatura_duplicada'
  ) as trigger_ativo;
