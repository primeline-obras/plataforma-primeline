begin;

alter table public.faturas
  add column if not exists aprovada_sem_guia boolean not null default false;

comment on column public.faturas.aprovada_sem_guia is
  'Regista que a fatura foi aprovada sem guia de remessa. Política temporária: permitido com aviso.';

-- Identifica também as faturas históricas já aprovadas sem qualquer guia.
update public.faturas f
set aprovada_sem_guia = true
where f.estado_aprovacao = 'aprovado'
  and not exists (
    select 1
    from public.faturas_guias fg
    where fg.fatura_id = f.id
  );

create or replace function public.fn_decidir_fatura(p_fatura_id uuid, p_decisao text)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fatura public.faturas;
  v_sem_guia boolean := false;
  -- Política temporária. Alterar apenas para TRUE para reativar o bloqueio anterior.
  v_bloquear_sem_guia constant boolean := false;
begin
  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;
  if not public.fn_pode_editar_obra(v_fatura.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;

  if p_decisao = 'aprovado' then
    v_sem_guia := not exists (
      select 1
      from public.faturas_guias
      where fatura_id = p_fatura_id
    );
  end if;

  -- A lógica de bloqueio fica preservada para uma futura reativação da regra.
  if v_bloquear_sem_guia and p_decisao = 'aprovado' and v_sem_guia then
    raise exception 'É obrigatório anexar pelo menos uma guia antes da aprovação.';
  end if;

  update public.faturas
  set estado_aprovacao = p_decisao,
      aprovado_por = null,
      data_aprovacao = now(),
      aprovada_sem_guia = case
        when p_decisao = 'aprovado' then v_sem_guia
        else false
      end
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$$;

revoke all on function public.fn_decidir_fatura(uuid, text) from public, anon;
grant execute on function public.fn_decidir_fatura(uuid, text) to authenticated;

commit;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'faturas'
      and column_name = 'aprovada_sem_guia'
  ) as indicador_sem_guia,
  position(
    'v_bloquear_sem_guia constant boolean := false'
    in pg_get_functiondef('public.fn_decidir_fatura(uuid,text)'::regprocedure)
  ) > 0 as bloqueio_temporariamente_desativado;
