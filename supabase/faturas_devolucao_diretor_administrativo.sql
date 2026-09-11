-- PRIMELINE GO | Diretor devolve fatura ao Administrativo com nota obrigatória
-- Executar integralmente no SQL Editor do Supabase depois de
-- faturas_acoes_financeiro_pos_pagamento.sql e faturas_observacao_aprovacao.sql.

begin;

alter table public.faturas
  add column if not exists observacao_devolucao text,
  add column if not exists devolvido_por uuid references public.utilizadores(id),
  add column if not exists devolvido_em timestamptz;

-- O estado próprio impede que o Diretor aprove novamente antes da correção.
-- Remove apenas a restrição conhecida do fluxo; outras regras da tabela ficam intactas.
alter table public.faturas drop constraint if exists faturas_estado_fluxo_check;

alter table public.faturas
  add constraint faturas_estado_fluxo_check check (estado_fluxo in (
    'recebida', 'em_validacao', 'aprovada_tecnicamente',
    'devolvida_administrativo', 'enviada_financeiro', 'paga'
  ));

-- Acrescenta os dois acontecimentos sem apagar o histórico financeiro existente.
alter table public.faturas_eventos drop constraint if exists faturas_eventos_tipo_check;

alter table public.faturas_eventos
  add constraint faturas_eventos_tipo_check check (tipo in (
    'paga', 'pagamento_revertido', 'devolvida', 'devolvida_administrativo',
    'corrigida_reenviada', 'anexo_adicionado'
  ));

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

  if old.estado_fluxo is distinct from new.estado_fluxo
     and new.estado_fluxo = 'devolvida_administrativo' then
    insert into public.faturas_eventos (fatura_id, tipo, observacao, utilizador_id)
    values (new.id, 'devolvida_administrativo', new.observacao_devolucao, public.fn_utilizador_atual_id());
  elsif old.estado_fluxo = 'devolvida_administrativo'
        and new.estado_fluxo = 'recebida' then
    insert into public.faturas_eventos (fatura_id, tipo, utilizador_id)
    values (new.id, 'corrigida_reenviada', public.fn_utilizador_atual_id());
  elsif old.estado_aprovacao = 'aprovado'
        and new.estado_aprovacao = 'pendente'
        and nullif(btrim(new.observacao_devolucao), '') is not null then
    insert into public.faturas_eventos (fatura_id, tipo, observacao, utilizador_id)
    values (new.id, 'devolvida', new.observacao_devolucao, public.fn_utilizador_atual_id());
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_eventos_financeiros_fatura on public.faturas;
create trigger trg_eventos_financeiros_fatura
after update of estado_aprovacao, estado_pagamento, estado_fluxo on public.faturas
for each row execute function public.fn_registar_evento_financeiro_fatura();

create or replace function public.fn_devolver_fatura_administrativo(
  p_fatura_id uuid,
  p_observacao text
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
  v_funcao text;
begin
  select funcao into v_funcao
  from public.utilizadores
  where id = public.fn_utilizador_atual_id()
    and coalesce(ativo, true);

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found then
    raise exception 'Fatura não encontrada.' using errcode = 'P0002';
  end if;
  if not (public.fn_e_admin() or v_funcao in ('diretor_obra', 'adjunto'))
     or not (public.fn_e_admin() or public.fn_pode_editar_obra(v_fatura.obra_id)) then
    raise exception 'A devolução está reservada ao Diretor ou Adjunto responsável pela obra.' using errcode = '42501';
  end if;
  if nullif(btrim(p_observacao), '') is null then
    raise exception 'A nota é obrigatória para devolver a fatura.';
  end if;
  if v_fatura.estado_fluxo not in ('recebida', 'em_validacao', 'aprovada_tecnicamente')
     or v_fatura.estado_pagamento = 'pago' then
    raise exception 'Esta fatura já não pode ser devolvida ao Administrativo.';
  end if;

  update public.faturas
  set estado_fluxo = 'devolvida_administrativo',
      estado_aprovacao = 'pendente',
      estado_pagamento = 'por_pagar',
      observacao_devolucao = btrim(p_observacao),
      devolvido_por = public.fn_utilizador_atual_id(),
      devolvido_em = now(),
      aprovado_por = null,
      data_aprovacao = null,
      aprovada_sem_guia = false
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;

revoke all on function public.fn_devolver_fatura_administrativo(uuid, text) from public, anon;
grant execute on function public.fn_devolver_fatura_administrativo(uuid, text) to authenticated;

-- Defesa no próprio banco: enquanto estiver devolvida nenhuma RPC antiga pode
-- aprovar ou avançar a fatura. Só uma correção administrativa a pode reabrir.
create or replace function public.fn_proteger_fatura_devolvida_administrativo()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if old.estado_fluxo = 'devolvida_administrativo'
     and (
       new.estado_fluxo is distinct from 'recebida'
       or not (public.fn_e_admin() or public.fn_e_administrativo())
     ) then
    raise exception 'A fatura aguarda correção do Administrativo e não pode ser aprovada.' using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_proteger_fatura_devolvida_administrativo() from public, anon, authenticated;
drop trigger if exists trg_proteger_fatura_devolvida_administrativo on public.faturas;
create trigger trg_proteger_fatura_devolvida_administrativo
before update of estado_fluxo, estado_aprovacao, estado_pagamento on public.faturas
for each row execute function public.fn_proteger_fatura_devolvida_administrativo();

-- Mantém a edição normal restrita ao autor, mas qualquer Administrativo pode
-- assumir uma fatura que lhe tenha sido formalmente devolvida.
create or replace function public.fn_editar_fatura_pendente(
  p_fatura_id uuid,
  p_obra_id uuid,
  p_tipo_origem text,
  p_fornecedor_id uuid,
  p_subempreitada_id uuid,
  p_numero_doc text,
  p_data_fatura date,
  p_valor numeric,
  p_condicao_pagamento text,
  p_data_vencimento date,
  p_itens jsonb default '[]'::jsonb
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_item jsonb;
  v_quantidade numeric;
  v_valor_unitario numeric;
  v_valor_total numeric;
  v_desconto_percentual numeric;
  v_valor_desconto numeric;
  v_foi_devolvida boolean;
begin
  select * into v_fatura from public.faturas where id = p_fatura_id for update;
  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente e não pode ser editada.';
  end if;
  v_foi_devolvida := v_fatura.estado_fluxo = 'devolvida_administrativo';

  if not public.fn_e_admin()
     and not (public.fn_e_administrativo() and (
       v_foi_devolvida or (v_fatura.criado_por is not null and v_fatura.criado_por = v_utilizador_id)
     )) then
    raise exception 'Só o Administrativo responsável pela correção ou a Gerência pode editar esta fatura.';
  end if;

  if p_obra_id is null or p_fornecedor_id is null
     or nullif(btrim(p_numero_doc), '') is null or p_data_fatura is null
     or p_valor is null or p_valor <= 0 then
    raise exception 'Preencha obra, fornecedor, número, data e valor da fatura.';
  end if;
  if p_tipo_origem not in ('subempreitada', 'material', 'estaleiro') then
    raise exception 'Tipo de despesa inválido.';
  end if;
  if p_condicao_pagamento not in ('imediato', '15_dias', '30_dias', 'outra_data') then
    raise exception 'Condição de pagamento inválida.';
  end if;
  if p_condicao_pagamento = 'outra_data' and p_data_vencimento is null then
    raise exception 'Indique a data de vencimento para a opção Outra data.';
  end if;
  if p_condicao_pagamento <> 'outra_data' and p_data_vencimento is not null then
    raise exception 'A data manual só pode ser usada com a opção Outra data.';
  end if;
  if p_tipo_origem = 'subempreitada' then
    if p_subempreitada_id is null or not exists (
      select 1 from public.subempreitadas s
      where s.id = p_subempreitada_id and s.obra_id = p_obra_id
        and s.fornecedor_id = p_fornecedor_id
    ) then
      raise exception 'A subempreitada não corresponde à obra e ao fornecedor selecionados.';
    end if;
  elsif p_subempreitada_id is not null then
    raise exception 'Faturas de material ou estaleiro não podem ter subempreitada associada.';
  end if;

  update public.faturas
  set obra_id = p_obra_id,
      tipo_origem = p_tipo_origem,
      fornecedor_id = p_fornecedor_id,
      subempreitada_id = p_subempreitada_id,
      numero_doc = btrim(p_numero_doc),
      data_fatura = p_data_fatura,
      valor = p_valor,
      condicao_pagamento = p_condicao_pagamento,
      data_vencimento = case when p_condicao_pagamento = 'outra_data' then p_data_vencimento else null end,
      estado_fluxo = case when v_foi_devolvida then 'recebida' else estado_fluxo end,
      observacao_devolucao = case when v_foi_devolvida then null else observacao_devolucao end,
      devolvido_por = case when v_foi_devolvida then null else devolvido_por end,
      devolvido_em = case when v_foi_devolvida then null else devolvido_em end
  where id = p_fatura_id
  returning * into v_fatura;

  delete from public.faturas_itens where fatura_id = p_fatura_id;
  if p_tipo_origem = 'material' then
    if jsonb_typeof(coalesce(p_itens, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) = 0 then
      raise exception 'Uma fatura de material exige pelo menos um artigo.';
    end if;
    for v_item in select value from jsonb_array_elements(p_itens)
    loop
      v_quantidade := nullif(v_item ->> 'quantidade', '')::numeric;
      v_valor_unitario := nullif(v_item ->> 'valor_unitario', '')::numeric;
      v_valor_total := nullif(v_item ->> 'valor_total', '')::numeric;
      v_desconto_percentual := nullif(v_item ->> 'desconto_percentual', '')::numeric;
      v_valor_desconto := nullif(v_item ->> 'valor_desconto', '')::numeric;
      if nullif(btrim(v_item ->> 'designacao'), '') is null
         or nullif(btrim(v_item ->> 'unidade'), '') is null
         or v_quantidade is null or v_quantidade <= 0
         or v_valor_unitario is null or v_valor_unitario < 0
         or v_valor_total is null or v_valor_total < 0
         or (v_desconto_percentual is not null and (v_desconto_percentual < 0 or v_desconto_percentual > 100))
         or (v_valor_desconto is not null and v_valor_desconto < 0) then
        raise exception 'Existe um artigo de material incompleto ou inválido.';
      end if;
      insert into public.faturas_itens (
        fatura_id, designacao, unidade, quantidade, valor_unitario, valor_total,
        desconto_percentual, valor_desconto
      ) values (
        p_fatura_id, btrim(v_item ->> 'designacao'), btrim(v_item ->> 'unidade'),
        v_quantidade, v_valor_unitario, v_valor_total,
        v_desconto_percentual, v_valor_desconto
      );
    end loop;
  end if;
  return v_fatura;
end;
$function$;

revoke all on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) from public, anon;
grant execute on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) to authenticated;

commit;

select
  to_regprocedure('public.fn_devolver_fatura_administrativo(uuid,text)') is not null as rpc_devolver_diretor,
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.faturas'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%devolvida_administrativo%'
  ) as estado_devolvida_ativo,
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.faturas_eventos'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%corrigida_reenviada%'
  ) as historico_completo;
