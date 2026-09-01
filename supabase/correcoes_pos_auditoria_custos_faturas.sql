-- PRIMELINE | Consolidação pós-auditoria: custos e fluxo de faturas
-- Migração aditiva. Executar depois de custos_estimados_modelo_final.sql.
begin;

-- Uma tarefa pode declarar explicitamente execução mista.
alter table public.planeamento_itens drop constraint if exists planeamento_itens_executado_por_check;
alter table public.planeamento_itens add constraint planeamento_itens_executado_por_check
  check (executado_por is null or executado_por in ('PL','subempreitada','misto'));

-- A sincronização liga adjudicação e especialidade, mas nunca decide o estado manual do custo.
create or replace function public.fn_sincronizar_componente_subempreitada()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_orcamento numeric:=0;
begin
  if new.subempreitada_id is null then return new; end if;
  select coalesce(sum(public.fn_valor_lancamento_custo(to_jsonb(io))),0) into v_orcamento
  from public.subempreitadas s
  join public.consultas_subempreitada_itens ci on ci.consulta_subempreitada_id=s.consulta_id
  join public.itens_orcamento io on io.id=ci.item_orcamento_id
  where s.id=new.subempreitada_id;

  insert into public.planeamento_custos_componentes(
    planeamento_item_id,especialidade_id,tipo,item_orcamento_id,subempreitada_id,valor_orcamentado,estado_custo
  ) values(new.id,new.especialidade_id,'subempreitada',null,new.subempreitada_id,v_orcamento,'orcamentado_nao_comprometido')
  on conflict (planeamento_item_id,tipo) where item_orcamento_id is null
  do update set especialidade_id=excluded.especialidade_id,
    subempreitada_id=excluded.subempreitada_id,
    valor_orcamentado=case when planeamento_custos_componentes.valor_orcamentado=0 then excluded.valor_orcamentado else planeamento_custos_componentes.valor_orcamentado end,
    atualizado_em=now();
  return new;
end;
$$;

-- O editor único aceita pacote ou linha de orçamento.
drop function if exists public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric);
create or replace function public.fn_guardar_componente_custo(
  p_planeamento_item_id uuid,p_tipo text,p_valor_orcamentado numeric,p_estado_custo text,
  p_valor_real_pl numeric,p_item_orcamento_id uuid
) returns public.planeamento_custos_componentes
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_obra_id uuid; v_item public.planeamento_itens%rowtype; v_row public.planeamento_custos_componentes%rowtype;
begin
  select * into v_item from public.planeamento_itens where id=p_planeamento_item_id;
  if not found then raise exception 'Tarefa de planeamento não encontrada.'; end if;
  select obra_id into v_obra_id from public.fases where id=v_item.fase_id;
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'A composição do custo só pode ser alterada pelo Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  if p_tipo not in ('PL','subempreitada') then raise exception 'Tipo de componente inválido.'; end if;
  if p_estado_custo not in ('orcamentado_nao_comprometido','em_consulta','adjudicado','em_execucao','concluido','cancelado') then raise exception 'Estado de custo inválido.'; end if;

  if p_item_orcamento_id is null then
    insert into public.planeamento_custos_componentes(planeamento_item_id,especialidade_id,tipo,item_orcamento_id,subempreitada_id,valor_orcamentado,valor_real_pl,estado_custo)
    values(v_item.id,v_item.especialidade_id,p_tipo,null,case when p_tipo='subempreitada' then v_item.subempreitada_id end,greatest(coalesce(p_valor_orcamentado,0),0),case when p_tipo='PL' then p_valor_real_pl end,p_estado_custo)
    on conflict (planeamento_item_id,tipo) where item_orcamento_id is null
    do update set especialidade_id=excluded.especialidade_id,subempreitada_id=excluded.subempreitada_id,
      valor_orcamentado=excluded.valor_orcamentado,valor_real_pl=excluded.valor_real_pl,
      estado_custo=excluded.estado_custo,atualizado_em=now() returning * into v_row;
  else
    insert into public.planeamento_custos_componentes(planeamento_item_id,especialidade_id,tipo,item_orcamento_id,subempreitada_id,valor_orcamentado,valor_real_pl,estado_custo)
    values(v_item.id,v_item.especialidade_id,p_tipo,p_item_orcamento_id,case when p_tipo='subempreitada' then v_item.subempreitada_id end,greatest(coalesce(p_valor_orcamentado,0),0),case when p_tipo='PL' then p_valor_real_pl end,p_estado_custo)
    on conflict (planeamento_item_id,tipo,item_orcamento_id) where item_orcamento_id is not null
    do update set especialidade_id=excluded.especialidade_id,subempreitada_id=excluded.subempreitada_id,
      valor_orcamentado=excluded.valor_orcamentado,valor_real_pl=excluded.valor_real_pl,
      estado_custo=excluded.estado_custo,atualizado_em=now() returning * into v_row;
  end if;
  return v_row;
end;
$$;
revoke all on function public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid) from public,anon;
grant execute on function public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid) to authenticated;

-- Concluir uma tarefa transfere todos os componentes PL para Custo Real pelo valor do orça.
create or replace function public.fn_concluir_custos_pl_tarefa(p_planeamento_item_id uuid)
returns setof public.planeamento_custos_componentes language plpgsql security definer set search_path=public,pg_temp as $$
declare v_obra_id uuid;
begin
  select f.obra_id into v_obra_id from public.planeamento_itens pi join public.fases f on f.id=pi.fase_id where pi.id=p_planeamento_item_id;
  if not found then raise exception 'Tarefa não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_obra_id) then raise exception 'Sem permissão para concluir esta tarefa.' using errcode='42501'; end if;
  return query update public.planeamento_custos_componentes
    set valor_real_pl=coalesce(valor_real_pl,valor_orcamentado),estado_custo='concluido',
      concluido_confirmado_em=coalesce(concluido_confirmado_em,now()),
      concluido_confirmado_por=coalesce(concluido_confirmado_por,public.fn_utilizador_atual_id()),atualizado_em=now()
    where planeamento_item_id=p_planeamento_item_id and tipo='PL' and estado_custo<>'cancelado' returning *;
end;
$$;
revoke all on function public.fn_concluir_custos_pl_tarefa(uuid) from public,anon;
grant execute on function public.fn_concluir_custos_pl_tarefa(uuid) to authenticated;

create or replace function public.fn_confirmar_remocao_custo_estimado_subempreitada(p_subempreitada_id uuid)
returns public.planeamento_custos_componentes language plpgsql security definer set search_path=public,pg_temp as $$
declare v_obra_id uuid; v_row public.planeamento_custos_componentes%rowtype;
begin
  select obra_id into v_obra_id from public.subempreitadas where id=p_subempreitada_id;
  if not found then raise exception 'Subempreitada não encontrada.'; end if;
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'A confirmação está reservada ao Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  update public.planeamento_custos_componentes set remocao_estimado_confirmada_em=now(),remocao_estimado_confirmada_por=public.fn_utilizador_atual_id(),
    estado_custo=case when estado_custo='orcamentado_nao_comprometido' then 'adjudicado' else estado_custo end,atualizado_em=now()
  where subempreitada_id=p_subempreitada_id and tipo='subempreitada' returning * into v_row;
  if not found then raise exception 'Componente de custo da subempreitada não encontrado.'; end if; return v_row;
end; $$;
revoke all on function public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) from public,anon;
grant execute on function public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) to authenticated;

-- Bloqueia alteração direta da venda contratual depois da criação.
create or replace function public.fn_bloquear_venda_contrato_direta()
returns trigger language plpgsql set search_path=public as $$
begin
  if (new.venda_contratual_inicial,new.venda_contratual_efetiva) is distinct from (old.venda_contratual_inicial,old.venda_contratual_efetiva)
     and coalesce(current_setting('primeline.alteracao_via_tee',true),'')<>'on' then
    raise exception 'O preço de venda só pode ser alterado por um TEE formal aprovado.' using errcode='42501';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_bloquear_venda_contrato_direta on public.contratos;
create trigger trg_bloquear_venda_contrato_direta before update of venda_contratual_inicial,venda_contratual_efetiva
on public.contratos for each row execute function public.fn_bloquear_venda_contrato_direta();

create or replace function public.fn_atualizar_venda_contrato_via_tee(p_tee_id uuid)
returns public.contratos language plpgsql security definer set search_path=public,pg_temp as $$
declare v_obra_id uuid; v_row public.contratos%rowtype;
begin
  select obra_id into v_obra_id from public.alteracoes_tee where id=p_tee_id and estado_aprovacao_cliente='aprovado';
  if not found then raise exception 'TEE formal aprovado não encontrado.'; end if;
  if not public.fn_e_diretor_obra(v_obra_id) then raise exception 'Operação reservada ao Diretor de Obra ou Gerência.' using errcode='42501'; end if;
  perform set_config('primeline.alteracao_via_tee','on',true);
  update public.contratos c set venda_contratual_efetiva=coalesce(c.venda_contratual_inicial,0)+
    coalesce((select sum(t.valor) from public.alteracoes_tee t where t.obra_id=v_obra_id and t.estado_aprovacao_cliente='aprovado'),0),atualizado_em=now()
  where c.obra_id=v_obra_id returning * into v_row;
  return v_row;
end;
$$;
revoke all on function public.fn_atualizar_venda_contrato_via_tee(uuid) from public,anon;
grant execute on function public.fn_atualizar_venda_contrato_via_tee(uuid) to authenticated;

create or replace function public.fn_recalcular_venda_contrato_tee_trigger()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.estado_aprovacao_cliente is distinct from old.estado_aprovacao_cliente then
    perform set_config('primeline.alteracao_via_tee','on',true);
    update public.contratos c set venda_contratual_efetiva=coalesce(c.venda_contratual_inicial,0)+
      coalesce((select sum(t.valor) from public.alteracoes_tee t where t.obra_id=new.obra_id and t.estado_aprovacao_cliente='aprovado'),0),
      atualizado_em=now() where c.obra_id=new.obra_id;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_recalcular_venda_contrato_tee on public.alteracoes_tee;
create trigger trg_recalcular_venda_contrato_tee after update of estado_aprovacao_cliente on public.alteracoes_tee
for each row execute function public.fn_recalcular_venda_contrato_tee_trigger();

-- Fonte única do resumo: só pagamentos aprovados/pagos; faturação é ao cliente.
create or replace function public.fn_resumo_custos_obra(p_obra_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_real_pl numeric:=0; v_real_sub numeric:=0; v_est_pl numeric:=0; v_est_sub numeric:=0; v_comp_sub numeric:=0;
  v_componentes jsonb:='[]'; v_ajustes jsonb:='[]'; v_ajustes_total numeric:=0;
  v_faturado_cliente numeric:=0; v_venda numeric:=0; v_adjudicado numeric:=0;
begin
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  with base as (
    select c.*,pi.descricao,e.nome especialidade,s.valor_adjudicado,
      coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id
        and lower(coalesce(to_jsonb(p)->>'estado_pagamento',to_jsonb(p)->>'estado_aprovacao','pago')) in ('pago','aprovado','aprovada')),0) pago_sub
    from public.planeamento_custos_componentes c join public.planeamento_itens pi on pi.id=c.planeamento_item_id
    join public.fases f on f.id=pi.fase_id left join public.especialidades e on e.id=c.especialidade_id
    left join public.subempreitadas s on s.id=c.subempreitada_id where f.obra_id=p_obra_id
  ) select
    coalesce(sum(case when tipo='PL' and estado_custo='concluido' then coalesce(valor_real_pl,valor_orcamentado) else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' then pago_sub else 0 end),0),
    coalesce(sum(case when tipo='PL' and estado_custo not in ('concluido','cancelado') then valor_orcamentado else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' and remocao_estimado_confirmada_em is null and estado_custo<>'cancelado' then valor_orcamentado else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' and remocao_estimado_confirmada_em is not null and estado_custo<>'cancelado' then greatest(coalesce(valor_adjudicado,0)-pago_sub,0) else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' then coalesce(valor_adjudicado,0) else 0 end),0),
    coalesce(jsonb_agg(jsonb_build_object('id',id,'planeamento_item_id',planeamento_item_id,'item_orcamento_id',item_orcamento_id,
      'descricao',descricao,'especialidade',coalesce(especialidade,'Sem especialidade'),'tipo',tipo,'valor_orcamentado',valor_orcamentado,
      'valor_adjudicado',coalesce(valor_adjudicado,0),'valor_real',case when tipo='PL' then coalesce(valor_real_pl,0) else pago_sub end,
      'compromisso_remanescente',case when tipo='subempreitada' and remocao_estimado_confirmada_em is not null then greatest(coalesce(valor_adjudicado,0)-pago_sub,0) else 0 end,
      'estado_custo',estado_custo,'subempreitada_id',subempreitada_id,'remocao_confirmada',remocao_estimado_confirmada_em is not null)),'[]')
  into v_real_pl,v_real_sub,v_est_pl,v_est_sub,v_comp_sub,v_adjudicado,v_componentes from base;

  select coalesce(sum(a.valor),0),coalesce(jsonb_agg(jsonb_build_object('id',a.id,'valor',a.valor,'motivo',a.motivo,'autor',u.nome,'criado_em',a.criado_em) order by a.criado_em desc),'[]')
    into v_ajustes_total,v_ajustes from public.ajustes_custo_obra a left join public.utilizadores u on u.id=a.criado_por where a.obra_id=p_obra_id;

  select coalesce(max(c.venda_contratual_efetiva),max(c.venda_contratual_inicial),0) into v_venda from public.contratos c where c.obra_id=p_obra_id;
  if to_regclass('public.faturacao') is not null then
    execute $q$select coalesce(sum(coalesce(nullif(j->>'valor_fatura','')::numeric,nullif(j->>'valor_a_faturar','')::numeric,nullif(j->>'valor','')::numeric,0)),0)
      from (select to_jsonb(f) j from public.faturacao f where f.obra_id=$1) x
      where lower(coalesce(j->>'estado_aprovacao',j->>'estado','aprovado')) in ('aprovado','aprovada','emitida','paga')$q$
      into v_faturado_cliente using p_obra_id;
  end if;
  return jsonb_build_object('obra_id',p_obra_id,'formula','Custo Real + Custos Estimados = Estimativa Final',
    'real',jsonb_build_object('pl',v_real_pl,'subempreitadas',v_real_sub,'total',v_real_pl+v_real_sub),
    'por_concluir',jsonb_build_object('pl',v_est_pl,'sub_orcamento_aguarda_confirmacao',v_est_sub,'sub_compromisso_remanescente',v_comp_sub,'total',v_est_pl+v_est_sub+v_comp_sub),
    'estimativa_terminus_direta',v_real_pl+v_real_sub+v_est_pl+v_est_sub+v_comp_sub,'custos_fixos',0,'pessoal_viatura_estimado',0,'ajustes_total',v_ajustes_total,
    'estimativa_terminus_total',v_real_pl+v_real_sub+v_est_pl+v_est_sub+v_comp_sub+v_ajustes_total,
    'percentagem_faturado',case when v_venda>0 then round(v_faturado_cliente*100/v_venda,2) else 0 end,
    'percentagem_pago',case when v_adjudicado>0 then round(v_real_sub*100/v_adjudicado,2) else 0 end,'componentes',v_componentes,'ajustes',v_ajustes);
end;
$$;

-- O modelo anterior deixa de ser uma API operacional.
do $$ begin
  if to_regprocedure('public.fn_resumo_custos_estimados_obra(uuid)') is not null then
    execute 'revoke execute on function public.fn_resumo_custos_estimados_obra(uuid) from authenticated';
  end if;
  if to_regprocedure('public.fn_confirmar_compromisso_subempreitada(uuid)') is not null then
    execute 'revoke execute on function public.fn_confirmar_compromisso_subempreitada(uuid) from authenticated';
  end if;
end $$;

-- Um único fluxo operativo de cinco estados, sem saltar diretamente da receção para o Financeiro.
alter table public.faturas add column if not exists estado_fluxo text;
update public.faturas set estado_fluxo=case
  when estado_pagamento='pago' then 'paga'
  when estado_aprovacao='aprovado' then 'enviada_financeiro'
  else 'recebida' end where estado_fluxo is null;
alter table public.faturas alter column estado_fluxo set default 'recebida';
alter table public.faturas alter column estado_fluxo set not null;
alter table public.faturas drop constraint if exists faturas_estado_fluxo_check;
alter table public.faturas add constraint faturas_estado_fluxo_check check (estado_fluxo in
  ('recebida','em_validacao','aprovada_tecnicamente','enviada_financeiro','paga'));

drop function if exists public.fn_avancar_estado_fluxo_fatura(uuid,text);
create or replace function public.fn_avancar_estado_fluxo_fatura(p_fatura_id uuid,p_novo_estado text,p_data_pagamento date default null)
returns public.faturas language plpgsql security definer set search_path=public,pg_temp as $$
declare v_fatura public.faturas; v_ordem text[]:=array['recebida','em_validacao','aprovada_tecnicamente','enviada_financeiro','paga'];
begin
  select * into v_fatura from public.faturas where id=p_fatura_id for update;
  if not found then raise exception 'Fatura não encontrada.'; end if;
  if array_position(v_ordem,p_novo_estado) is null
     or array_position(v_ordem,p_novo_estado)<>array_position(v_ordem,v_fatura.estado_fluxo)+1 then
    raise exception 'A fatura deve seguir os cinco estados pela ordem definida.';
  end if;
  if p_novo_estado='paga' then
    if not public.fn_e_financeiro() then raise exception 'Só o Financeiro pode marcar a fatura como paga.' using errcode='42501'; end if;
  elsif not (public.fn_pode_editar_obra(v_fatura.obra_id) or public.fn_e_admin()) then
    raise exception 'Sem permissão para avançar a validação desta fatura.' using errcode='42501';
  end if;
  update public.faturas set estado_fluxo=p_novo_estado,
    estado_aprovacao=case when p_novo_estado in ('aprovada_tecnicamente','enviada_financeiro','paga') then 'aprovado' else 'pendente' end,
    estado_pagamento=case when p_novo_estado='paga' then 'pago' else 'por_pagar' end,
    data_aprovacao=case when p_novo_estado='aprovada_tecnicamente' then now() else data_aprovacao end,
    aprovado_por=case when p_novo_estado='aprovada_tecnicamente' then public.fn_utilizador_atual_id() else aprovado_por end,
    data_pagamento=case when p_novo_estado='paga' then coalesce(p_data_pagamento,data_pagamento,current_date) else data_pagamento end
  where id=p_fatura_id returning * into v_fatura;
  return v_fatura;
end;
$$;
revoke all on function public.fn_avancar_estado_fluxo_fatura(uuid,text,date) from public,anon;
grant execute on function public.fn_avancar_estado_fluxo_fatura(uuid,text,date) to authenticated;

create or replace function public.fn_apagar_guia_fatura(p_guia_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_path text; v_obra uuid;
begin
  select g.arquivo_url,f.obra_id into v_path,v_obra from public.faturas_guias g join public.faturas f on f.id=g.fatura_id where g.id=p_guia_id;
  if not found then raise exception 'Guia não encontrada.'; end if;
  if not (public.fn_pode_editar_obra(v_obra) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.faturas_guias where id=p_guia_id;
  return v_path;
end;
$$;
create or replace function public.fn_apagar_anexo_fatura(p_anexo_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_path text; v_obra uuid;
begin
  select a.arquivo_url,f.obra_id into v_path,v_obra from public.faturas_anexos a join public.faturas f on f.id=a.fatura_id where a.id=p_anexo_id;
  if not found then raise exception 'Anexo não encontrado.'; end if;
  if not (public.fn_pode_editar_obra(v_obra) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.faturas_anexos where id=p_anexo_id;
  return v_path;
end;
$$;
revoke all on function public.fn_apagar_guia_fatura(uuid) from public,anon;
revoke all on function public.fn_apagar_anexo_fatura(uuid) from public,anon;
grant execute on function public.fn_apagar_guia_fatura(uuid) to authenticated;
grant execute on function public.fn_apagar_anexo_fatura(uuid) to authenticated;
drop policy if exists faturas_storage_delete_restrito on storage.objects;
create policy faturas_storage_delete_restrito on storage.objects for delete to authenticated
using (bucket_id='faturas' and (public.fn_e_admin() or exists(select 1 from public.utilizadores u where u.auth_user_id=auth.uid() and u.ativo and u.funcao in ('administrativo','financeiro','diretor_obra','adjunto','preparador'))));

-- RNC: edição dos dados-base, cancelamento lógico e eliminação controlada de evidências.
alter table public.rnc drop constraint if exists rnc_estado_check;
alter table public.rnc add constraint rnc_estado_check check (estado in ('aberto','em_correcao','verificado','fechado','cancelado'));
create or replace function public.fn_editar_rnc_base(p_rnc_id uuid,p_data_deteccao date,p_local_ocorrencia text,p_descricao text,p_gravidade text)
returns public.rnc language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.rnc;
begin
  select * into v_row from public.rnc where id=p_rnc_id for update;
  if not found then raise exception 'RNC não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_row.obra_id) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  if nullif(btrim(p_descricao),'') is null or p_gravidade not in ('critica','maior','menor') then raise exception 'Dados da RNC inválidos.'; end if;
  update public.rnc set data_deteccao=coalesce(p_data_deteccao,data_deteccao),local_ocorrencia=nullif(btrim(p_local_ocorrencia),''),descricao=btrim(p_descricao),gravidade=p_gravidade
  where id=p_rnc_id returning * into v_row; return v_row;
end; $$;
create or replace function public.fn_cancelar_rnc(p_rnc_id uuid)
returns public.rnc language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.rnc;
begin
  select * into v_row from public.rnc where id=p_rnc_id for update;
  if not found then raise exception 'RNC não encontrada.'; end if;
  if not public.fn_pode_editar_obra(v_row.obra_id) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  update public.rnc set estado='cancelado' where id=p_rnc_id returning * into v_row; return v_row;
end; $$;
create or replace function public.fn_apagar_anexo_rnc(p_anexo_id uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_path text; v_obra uuid;
begin
  select a.arquivo_url,r.obra_id into v_path,v_obra from public.rnc_anexos a join public.rnc r on r.id=a.rnc_id where a.id=p_anexo_id;
  if not found then raise exception 'Anexo não encontrado.'; end if;
  if not public.fn_pode_editar_obra(v_obra) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.rnc_anexos where id=p_anexo_id; return v_path;
end; $$;
revoke all on function public.fn_editar_rnc_base(uuid,date,text,text,text) from public,anon;
revoke all on function public.fn_cancelar_rnc(uuid) from public,anon;
revoke all on function public.fn_apagar_anexo_rnc(uuid) from public,anon;
grant execute on function public.fn_editar_rnc_base(uuid,date,text,text,text) to authenticated;
grant execute on function public.fn_cancelar_rnc(uuid) to authenticated;
grant execute on function public.fn_apagar_anexo_rnc(uuid) to authenticated;

-- Frota: edição e eliminação restritas a Administrativo/Gerência.
create or replace function public.fn_gerir_registo_frota(p_tabela text,p_registo_id uuid,p_acao text,p_dados jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row jsonb;
begin
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Operação reservada a Administrativo/Gerência.' using errcode='42501'; end if;
  if p_acao not in ('editar','apagar') then raise exception 'Ação inválida.'; end if;
  if p_tabela='viaturas_eventos' then
    if p_acao='editar' then update public.viaturas_eventos set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row;
    else delete from public.viaturas_eventos where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row; end if;
  elsif p_tabela='viaturas_sinistros' then
    if p_acao='editar' then update public.viaturas_sinistros set descricao=coalesce(nullif(btrim(p_dados->>'descricao'),''),descricao),estado=case when p_dados ? 'estado' and p_dados->>'estado' in ('aberto','em_seguradora','fechado') then p_dados->>'estado' else estado end where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row;
    else delete from public.viaturas_sinistros where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row; end if;
  elsif p_tabela='multas' then
    if p_acao='editar' then update public.multas set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(multas) into v_row;
    else delete from public.multas where id=p_registo_id returning to_jsonb(multas) into v_row; end if;
  elsif p_tabela='viaturas_sinistros_anexos' and p_acao='apagar' then delete from public.viaturas_sinistros_anexos where id=p_registo_id returning to_jsonb(viaturas_sinistros_anexos) into v_row;
  elsif p_tabela='multas_anexos' and p_acao='apagar' then delete from public.multas_anexos where id=p_registo_id returning to_jsonb(multas_anexos) into v_row;
  else raise exception 'Tabela de frota não autorizada.'; end if;
  if v_row is null then raise exception 'Registo não encontrado.'; end if;
  return v_row;
end; $$;
revoke all on function public.fn_gerir_registo_frota(text,uuid,text,jsonb) from public,anon;
grant execute on function public.fn_gerir_registo_frota(text,uuid,text,jsonb) to authenticated;

do $$ declare v_tabela text; begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    foreach v_tabela in array array['rnc','rnc_anexos','faturas_guias','faturas_anexos','viaturas_eventos','viaturas_sinistros','viaturas_sinistros_anexos','multas','multas_anexos'] loop
      execute format('drop trigger if exists %I on public.%I','trg_auditoria_'||v_tabela,v_tabela);
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.fn_registar_log_auditoria(''id'')','trg_auditoria_'||v_tabela,v_tabela);
    end loop;
  end if;
end $$;

-- Imóveis: edição de dados/reuniões e anexos privados com eliminação auditada.
grant update on public.imoveis_empresa,public.imoveis_reunioes_condominio to authenticated;
drop policy if exists imoveis_empresa_update on public.imoveis_empresa;
create policy imoveis_empresa_update on public.imoveis_empresa for update to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo()) with check (public.fn_e_admin() or public.fn_e_administrativo());
drop policy if exists imoveis_reunioes_update on public.imoveis_reunioes_condominio;
create policy imoveis_reunioes_update on public.imoveis_reunioes_condominio for update to authenticated
using (public.fn_e_admin() or public.fn_e_administrativo()) with check (public.fn_e_admin() or public.fn_e_administrativo());
create table if not exists public.imoveis_anexos(
  id uuid primary key default gen_random_uuid(),imovel_id uuid not null references public.imoveis_empresa(id) on delete cascade,
  arquivo_url text not null,nome_arquivo text not null,criado_por uuid default public.fn_utilizador_atual_id(),criado_em timestamptz not null default now());
alter table public.imoveis_anexos enable row level security;
grant select,insert on public.imoveis_anexos to authenticated;
drop policy if exists imoveis_anexos_select on public.imoveis_anexos;
create policy imoveis_anexos_select on public.imoveis_anexos for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());
drop policy if exists imoveis_anexos_insert on public.imoveis_anexos;
create policy imoveis_anexos_insert on public.imoveis_anexos for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());
create or replace function public.fn_apagar_anexo_imovel(p_anexo_id uuid) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_path text; begin if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.imoveis_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $$;
revoke all on function public.fn_apagar_anexo_imovel(uuid) from public,anon; grant execute on function public.fn_apagar_anexo_imovel(uuid) to authenticated;
drop policy if exists entidades_documentos_insert on storage.objects;
create policy entidades_documentos_insert on storage.objects for insert to authenticated with check (bucket_id='documentos' and name like 'entidades/%' and (public.fn_e_admin() or public.fn_e_administrativo()));
drop policy if exists entidades_documentos_select on storage.objects;
create policy entidades_documentos_select on storage.objects for select to authenticated using (bucket_id='documentos' and name like 'entidades/%' and (public.fn_e_admin() or public.fn_e_administrativo()));
drop policy if exists entidades_documentos_delete on storage.objects;
create policy entidades_documentos_delete on storage.objects for delete to authenticated using (bucket_id='documentos' and name like 'entidades/%' and (public.fn_e_admin() or public.fn_e_administrativo()));
do $$ begin if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
  drop trigger if exists trg_auditoria_imoveis_anexos on public.imoveis_anexos;
  create trigger trg_auditoria_imoveis_anexos after insert or update or delete on public.imoveis_anexos for each row execute function public.fn_registar_log_auditoria('id');
end if; end $$;

-- Pedidos de orçamento: anexos no pedido e em cada versão.
create table if not exists public.pedidos_orcamento_anexos(
  id uuid primary key default gen_random_uuid(),pedido_id uuid not null references public.pedidos_orcamento(id) on delete cascade,
  versao_id uuid references public.pedidos_orcamento_versoes(id) on delete cascade,arquivo_url text not null,nome_arquivo text not null,
  criado_por uuid default public.fn_utilizador_atual_id(),criado_em timestamptz not null default now());
alter table public.pedidos_orcamento_anexos enable row level security;
grant select,insert on public.pedidos_orcamento_anexos to authenticated;
drop policy if exists pedidos_orcamento_anexos_select on public.pedidos_orcamento_anexos;
create policy pedidos_orcamento_anexos_select on public.pedidos_orcamento_anexos for select to authenticated using (public.fn_e_admin() or public.fn_e_administrativo());
drop policy if exists pedidos_orcamento_anexos_insert on public.pedidos_orcamento_anexos;
create policy pedidos_orcamento_anexos_insert on public.pedidos_orcamento_anexos for insert to authenticated with check (public.fn_e_admin() or public.fn_e_administrativo());
create or replace function public.fn_apagar_anexo_pedido_orcamento(p_anexo_id uuid) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_path text; begin if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.pedidos_orcamento_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $$;
revoke all on function public.fn_apagar_anexo_pedido_orcamento(uuid) from public,anon; grant execute on function public.fn_apagar_anexo_pedido_orcamento(uuid) to authenticated;
do $$ begin if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
  drop trigger if exists trg_auditoria_pedidos_orcamento_anexos on public.pedidos_orcamento_anexos;
  create trigger trg_auditoria_pedidos_orcamento_anexos after insert or update or delete on public.pedidos_orcamento_anexos for each row execute function public.fn_registar_log_auditoria('id');
end if; end $$;

commit;

select to_regprocedure('public.fn_resumo_custos_obra(uuid)') is not null as resumo_unico,
       to_regprocedure('public.fn_concluir_custos_pl_tarefa(uuid)') is not null as conclusao_pl_automatica;
