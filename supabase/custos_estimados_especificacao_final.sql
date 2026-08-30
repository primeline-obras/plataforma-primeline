-- PRIMELINE | Custos estimados — especificação final corrigida
-- Não cria "Outros custos", não exige auto de medição e não associa materiais/mão de obra a tarefas.
begin;

alter table public.planeamento_itens
  add column if not exists especialidade_id uuid,
  add column if not exists item_orcamento_id uuid references public.itens_orcamento(id) on delete set null,
  add column if not exists custo_estado text not null default 'orcamentado',
  add column if not exists valor_estimado numeric,
  add column if not exists compromisso_confirmado boolean not null default false,
  add column if not exists compromisso_confirmado_por uuid references public.utilizadores(id),
  add column if not exists compromisso_confirmado_em timestamptz;

alter table public.planeamento_itens
  drop constraint if exists planeamento_itens_custo_estado_check,
  add constraint planeamento_itens_custo_estado_check check (custo_estado = any(array[
    'orcamentado'::text, 'em_consulta'::text, 'adjudicado'::text,
    'em_execucao'::text, 'concluido'::text, 'cancelado'::text
  ])),
  drop constraint if exists planeamento_itens_valor_estimado_check,
  add constraint planeamento_itens_valor_estimado_check check (valor_estimado is null or valor_estimado >= 0);

create index if not exists planeamento_itens_especialidade_idx on public.planeamento_itens(especialidade_id);
create index if not exists planeamento_itens_orcamento_idx on public.planeamento_itens(item_orcamento_id);

create or replace function public.fn_confirmar_compromisso_subempreitada(p_planeamento_item_id uuid)
returns public.planeamento_itens language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_item public.planeamento_itens; v_obra_id uuid; v_sub public.subempreitadas; v_utilizador_id uuid;
begin
  select pi, fase.obra_id, s into v_item, v_obra_id, v_sub
  from public.planeamento_itens pi join public.fases fase on fase.id=pi.fase_id
  join public.subempreitadas s on s.id=pi.subempreitada_id
  where pi.id=p_planeamento_item_id for update of pi;
  if not found then raise exception 'Tarefa/pacote de subempreitada não encontrado.'; end if;
  if not public.fn_pode_editar_obra(v_obra_id) then raise exception 'Só a equipa técnica responsável pode confirmar este compromisso.'; end if;
  if lower(coalesce(v_sub.estado,'')) not in ('adjudicada','adjudicado','em_execucao','concluida','concluido') then raise exception 'A subempreitada ainda não está adjudicada.'; end if;
  select id into v_utilizador_id from public.utilizadores where auth_user_id=auth.uid() limit 1;
  update public.planeamento_itens set compromisso_confirmado=true,
    compromisso_confirmado_por=v_utilizador_id, compromisso_confirmado_em=now(), custo_estado='adjudicado'
  where id=p_planeamento_item_id returning * into v_item;
  return v_item;
end;$function$;

revoke all on function public.fn_confirmar_compromisso_subempreitada(uuid) from public,anon;
grant execute on function public.fn_confirmar_compromisso_subempreitada(uuid) to authenticated;

-- O preço de venda fechado só muda por TE formal. Uma futura RPC de TE poderá
-- usar set_config('primeline.alteracao_via_tee','on',true) durante a alteração.
create or replace function public.fn_proteger_preco_venda_subempreitada()
returns trigger language plpgsql set search_path=public,pg_temp as $function$
declare v_old jsonb:=to_jsonb(old); v_new jsonb:=to_jsonb(new); v_campo text;
begin
  if current_setting('primeline.alteracao_via_tee',true)='on' then return new; end if;
  foreach v_campo in array array['preco_venda','valor_venda','valor_contrato'] loop
    if v_old ? v_campo and (v_new->>v_campo) is distinct from (v_old->>v_campo) then
      raise exception 'O Preço de Venda fechado só pode ser alterado através de um TE formal.';
    end if;
  end loop;
  return new;
end;$function$;

drop trigger if exists trg_proteger_preco_venda_subempreitada on public.subempreitadas;
create trigger trg_proteger_preco_venda_subempreitada before update on public.subempreitadas
for each row execute function public.fn_proteger_preco_venda_subempreitada();

create or replace function public.fn_resumo_custos_estimados_obra(p_obra_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare
  v_orc_material numeric:=0; v_orc_mao_obra numeric:=0; v_real_material numeric:=0; v_real_mao_obra numeric:=0;
  v_estimado_pacotes numeric:=0; v_compromisso numeric:=0; v_real_sub numeric:=0; v_pago_sub numeric:=0;
  v_linha record; v_json jsonb; v_texto text; v_valor numeric; v_pacotes jsonb:='[]'::jsonb;
begin
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_financeiro()) then raise exception 'Sem acesso aos custos desta obra.'; end if;

  for v_linha in select to_jsonb(io) dados from public.itens_orcamento io join public.fases f on f.id=io.fase_id where f.obra_id=p_obra_id loop
    v_json:=v_linha.dados;
    v_texto:=lower(concat_ws(' ',v_json->>'especialidade',v_json->>'capitulo',v_json->>'subcapitulo',v_json->>'designacao',v_json->>'descricao'));
    v_valor:=coalesce(nullif(v_json->>'custo_direto','')::numeric,nullif(v_json->>'preco_custo','')::numeric,nullif(v_json->>'valor_custo','')::numeric,nullif(v_json->>'valor_total','')::numeric,0);
    if v_texto like '%material%' then v_orc_material:=v_orc_material+v_valor;
    elsif v_texto like '%mão de obra%' or v_texto like '%mao de obra%' or v_texto like '%pessoal%' then v_orc_mao_obra:=v_orc_mao_obra+v_valor; end if;
  end loop;

  if to_regclass('public.lancamentos_materiais') is not null then
    for v_linha in execute 'select to_jsonb(t) dados from public.lancamentos_materiais t where (to_jsonb(t)->>''obra_id'')::uuid=$1' using p_obra_id loop
      v_json:=v_linha.dados;
      v_real_material:=v_real_material+coalesce(nullif(v_json->>'valor_total','')::numeric,nullif(v_json->>'valor','')::numeric,nullif(v_json->>'total','')::numeric,0);
    end loop;
  else
    select coalesce(sum(valor),0) into v_real_material from public.faturas where obra_id=p_obra_id and tipo_origem='material';
  end if;

  select coalesce(sum(coalesce(valor_total,horas*valor_hora,0)),0) into v_real_mao_obra
  from public.lancamentos_mao_obra where obra_id=p_obra_id;

  for v_linha in
    select pi.id,pi.codigo,pi.descricao,pi.valor_estimado,pi.compromisso_confirmado,pi.custo_estado,
      s.id subempreitada_id,s.valor_adjudicado,s.estado,
      coalesce((select sum(fat.valor) from public.faturas fat where fat.subempreitada_id=s.id and coalesce(fat.fluxo_estado,'recebida') in ('aprovada_tecnicamente','enviada_financeiro','paga')),0) faturado,
      coalesce((select sum(fat.valor) from public.faturas fat where fat.subempreitada_id=s.id and (coalesce(fat.fluxo_estado,'')='paga' or fat.estado_pagamento='pago')),0) pago
    from public.planeamento_itens pi join public.fases f on f.id=pi.fase_id
    left join public.subempreitadas s on s.id=pi.subempreitada_id where f.obra_id=p_obra_id
  loop
    v_valor:=coalesce(v_linha.valor_estimado,v_linha.valor_adjudicado,0);
    if v_linha.subempreitada_id is null or not v_linha.compromisso_confirmado then
      if v_linha.custo_estado<>'cancelado' then v_estimado_pacotes:=v_estimado_pacotes+v_valor; end if;
    else
      v_real_sub:=v_real_sub+v_linha.faturado;
      v_compromisso:=v_compromisso+greatest(coalesce(v_linha.valor_adjudicado,0)-v_linha.faturado,0);
      v_pago_sub:=v_pago_sub+v_linha.pago;
    end if;
    v_pacotes:=v_pacotes||jsonb_build_array(jsonb_build_object(
      'planeamento_item_id',v_linha.id,'codigo',v_linha.codigo,'descricao',v_linha.descricao,
      'valor_estimado',v_valor,'valor_adjudicado',coalesce(v_linha.valor_adjudicado,0),
      'confirmacao_pendente',(v_linha.subempreitada_id is not null and not v_linha.compromisso_confirmado and lower(coalesce(v_linha.estado,'')) in ('adjudicada','adjudicado','em_execucao','concluida','concluido')),
      'custo_real',case when v_linha.compromisso_confirmado then v_linha.faturado else 0 end,
      'compromisso_remanescente',case when v_linha.compromisso_confirmado then greatest(coalesce(v_linha.valor_adjudicado,0)-v_linha.faturado,0) else 0 end,
      'percentual_faturado',case when coalesce(v_linha.valor_adjudicado,0)>0 then round(v_linha.faturado/v_linha.valor_adjudicado*100,2) else 0 end,
      'percentual_pago',case when coalesce(v_linha.valor_adjudicado,0)>0 then round(v_linha.pago/v_linha.valor_adjudicado*100,2) else 0 end));
  end loop;

  return jsonb_build_object(
    'materiais',jsonb_build_object('orcamento',v_orc_material,'realizado',v_real_material,'estimado_remanescente',greatest(v_orc_material-v_real_material,0)),
    'mao_obra',jsonb_build_object('orcamento',v_orc_mao_obra,'realizado',v_real_mao_obra,'estimado_remanescente',greatest(v_orc_mao_obra-v_real_mao_obra,0)),
    'subempreitadas',jsonb_build_object('custo_real',v_real_sub,'compromisso_remanescente',v_compromisso,'pago',v_pago_sub),
    'total_estimado_remanescente',greatest(v_orc_material-v_real_material,0)+greatest(v_orc_mao_obra-v_real_mao_obra,0)+v_estimado_pacotes,
    'pacotes',v_pacotes);
end;$function$;

revoke all on function public.fn_resumo_custos_estimados_obra(uuid) from public,anon;
grant execute on function public.fn_resumo_custos_estimados_obra(uuid) to authenticated;

alter table public.faturas add column if not exists fluxo_estado text;
update public.faturas set fluxo_estado=case when estado_pagamento='pago' then 'paga' when estado_aprovacao='aprovado' then 'enviada_financeiro' when estado_aprovacao='recusado' then 'em_validacao' else 'recebida' end where fluxo_estado is null;
alter table public.faturas alter column fluxo_estado set default 'recebida';
alter table public.faturas alter column fluxo_estado set not null;
alter table public.faturas drop constraint if exists faturas_fluxo_estado_check;
alter table public.faturas add constraint faturas_fluxo_estado_check check (fluxo_estado=any(array['recebida'::text,'em_validacao'::text,'aprovada_tecnicamente'::text,'enviada_financeiro'::text,'paga'::text]));

create or replace function public.fn_avancar_fluxo_fatura(p_fatura_id uuid,p_novo_estado text)
returns public.faturas language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_fatura public.faturas; v_ordem text[]:=array['recebida','em_validacao','aprovada_tecnicamente','enviada_financeiro','paga'];
begin
  select * into v_fatura from public.faturas where id=p_fatura_id for update;
  if not found then raise exception 'Fatura não encontrada.'; end if;
  if array_position(v_ordem,p_novo_estado) is null or array_position(v_ordem,p_novo_estado)<>array_position(v_ordem,v_fatura.fluxo_estado)+1 then raise exception 'A fatura deve seguir as cinco etapas pela ordem definida.'; end if;
  if p_novo_estado='paga' and not public.fn_e_financeiro() then raise exception 'Só o Financeiro pode marcar a fatura como paga.'; end if;
  if p_novo_estado<>'paga' and not (public.fn_pode_editar_obra(v_fatura.obra_id) or public.fn_e_administrativo() or public.fn_e_admin() or public.fn_e_financeiro()) then raise exception 'Sem permissão para avançar esta fatura.'; end if;
  update public.faturas set fluxo_estado=p_novo_estado,
    estado_aprovacao=case when p_novo_estado in ('aprovada_tecnicamente','enviada_financeiro','paga') then 'aprovado' else 'pendente' end,
    estado_pagamento=case when p_novo_estado='paga' then 'pago' else 'por_pagar' end,
    data_pagamento=case when p_novo_estado='paga' then coalesce(data_pagamento,current_date) else data_pagamento end
  where id=p_fatura_id returning * into v_fatura;
  return v_fatura;
end;$function$;

revoke all on function public.fn_avancar_fluxo_fatura(uuid,text) from public,anon;
grant execute on function public.fn_avancar_fluxo_fatura(uuid,text) to authenticated;

commit;

select
  to_regprocedure('public.fn_resumo_custos_estimados_obra(uuid)') is not null as rpc_resumo_custos,
  to_regprocedure('public.fn_confirmar_compromisso_subempreitada(uuid)') is not null as rpc_confirmar_subempreitada,
  (select count(*) from information_schema.columns where table_schema='public' and table_name='faturas' and column_name='fluxo_estado')=1 as fluxo_faturas;
