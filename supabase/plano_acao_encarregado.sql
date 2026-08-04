-- PRIMELINE | Plano de ação e atualização restrita pelo encarregado.
-- Executar no SQL Editor depois de tees_previsao_encarregados.sql.

begin;

alter table public.planeamento_itens
  add column if not exists impedido boolean not null default false,
  add column if not exists observacao_impedimento text;

alter table public.planeamento_itens
  drop constraint if exists planeamento_itens_impedimento_observacao_check;
alter table public.planeamento_itens
  add constraint planeamento_itens_impedimento_observacao_check
  check (
    not impedido
    or nullif(btrim(observacao_impedimento), '') is not null
  );

-- Não é criada nenhuma policy UPDATE para encarregados. A equipa técnica
-- mantém as policies existentes e o encarregado passa exclusivamente pela RPC.
create or replace function public.fn_atualizar_tarefa_encarregado(
  p_item_id uuid,
  p_concluida boolean,
  p_impedido boolean,
  p_observacao_impedimento text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.planeamento_itens%rowtype;
  v_obra_id uuid;
begin
  if coalesce(p_concluida, false) and coalesce(p_impedido, false) then
    raise exception 'Uma tarefa concluída não pode ficar impedida.';
  end if;

  select pi, f.obra_id
    into v_item, v_obra_id
  from public.planeamento_itens pi
  join public.fases f on f.id = pi.fase_id
  where pi.id = p_item_id
  for update of pi;

  if not found then
    raise exception 'Tarefa de planeamento não encontrada.';
  end if;

  if not public.fn_e_encarregado_da_obra(v_obra_id) then
    raise exception 'Sem permissão para atualizar esta tarefa.';
  end if;

  if coalesce(p_impedido, false)
     and nullif(btrim(p_observacao_impedimento), '') is null then
    raise exception 'Explique por que motivo a tarefa não pode ser executada.';
  end if;

  update public.planeamento_itens
  set estado = case
        when coalesce(p_concluida, false) then 'concluido'
        when data_inicio_prevista is not null and data_inicio_prevista <= current_date
          then 'em_execucao'
        else 'por_iniciar'
      end,
      data_fim_real = case
        when coalesce(p_concluida, false) then current_date
        else null
      end,
      impedido = coalesce(p_impedido, false),
      observacao_impedimento = case
        when coalesce(p_impedido, false) then btrim(p_observacao_impedimento)
        else null
      end
  where id = p_item_id
  returning * into v_item;

  return to_jsonb(v_item);
end;
$$;

revoke all on function public.fn_atualizar_tarefa_encarregado(uuid, boolean, boolean, text)
  from public, anon;
grant execute on function public.fn_atualizar_tarefa_encarregado(uuid, boolean, boolean, text)
  to authenticated;

create or replace function public.fn_alertar_tarefa_impedida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_obra_id uuid;
  v_empresa_id uuid;
  v_obra_numero text;
begin
  select o.id, o.empresa_id, o.numero::text
    into v_obra_id, v_empresa_id, v_obra_numero
  from public.fases f
  join public.obras o on o.id = f.obra_id
  where f.id = new.fase_id;

  insert into public.alertas (
    empresa_id, obra_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  ) values (
    v_empresa_id,
    v_obra_id,
    'tarefa_impedida',
    'planeamento_itens',
    new.id,
    'URGENTE · Tarefa impedida' || coalesce(' · Obra ' || v_obra_numero, ''),
    new.descricao || ' — ' || btrim(new.observacao_impedimento),
    current_date,
    0,
    current_date,
    'diretor_obra',
    'pendente'
  );

  return new;
end;
$$;

revoke all on function public.fn_alertar_tarefa_impedida() from public, anon;

drop trigger if exists trg_alertar_tarefa_impedida on public.planeamento_itens;
create trigger trg_alertar_tarefa_impedida
after update of impedido on public.planeamento_itens
for each row
when (old.impedido is distinct from true and new.impedido is true)
execute function public.fn_alertar_tarefa_impedida();

commit;

select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'planeamento_itens'
      and column_name in ('impedido', 'observacao_impedimento')) as colunas_impedimento,
  (select count(*) from pg_proc where proname = 'fn_atualizar_tarefa_encarregado') as rpc_restrita,
  (select count(*) from pg_trigger
    where tgname = 'trg_alertar_tarefa_impedida' and not tgisinternal) as trigger_alerta;
