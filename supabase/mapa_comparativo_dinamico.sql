-- PRIMELINE GO | Mapa Comparativo de Subempreitadas e Fornecedores
-- Estrutura relacional com número dinâmico de propostas.
begin;

create table if not exists public.mapas_comparativos (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  especialidade text not null check (btrim(especialidade) <> ''),
  descricao text,
  custo_estimado_orcamento numeric check (custo_estimado_orcamento is null or custo_estimado_orcamento >= 0),
  melhor_preco_comparativo numeric not null default 0 check (melhor_preco_comparativo >= 0),
  valor_adjudicado_real numeric check (valor_adjudicado_real is null or valor_adjudicado_real >= 0),
  diferenca_negociacao numeric generated always as (
    case when valor_adjudicado_real is null then null
         else valor_adjudicado_real - melhor_preco_comparativo end
  ) stored,
  desvio_orcamento_valor numeric generated always as (
    case when valor_adjudicado_real is null or custo_estimado_orcamento is null then null
         else valor_adjudicado_real - custo_estimado_orcamento end
  ) stored,
  desvio_orcamento_percentual numeric generated always as (
    case when valor_adjudicado_real is null or nullif(custo_estimado_orcamento, 0) is null then null
         else (valor_adjudicado_real - custo_estimado_orcamento) / custo_estimado_orcamento * 100 end
  ) stored,
  preco_venda numeric check (preco_venda is null or preco_venda >= 0),
  margem_real_valor numeric generated always as (
    case when preco_venda is null or valor_adjudicado_real is null then null
         else preco_venda - valor_adjudicado_real end
  ) stored,
  margem_real_percentual numeric generated always as (
    case when valor_adjudicado_real is null or nullif(preco_venda, 0) is null then null
         else (preco_venda - valor_adjudicado_real) / preco_venda * 100 end
  ) stored,
  criado_por uuid references public.utilizadores(id) default public.fn_utilizador_atual_id(),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.comparativo_propostas (
  id uuid primary key default gen_random_uuid(),
  mapa_id uuid not null references public.mapas_comparativos(id) on delete cascade,
  fornecedor_id uuid not null references public.fornecedores(id),
  data_proposta date,
  contacto text,
  telemovel text,
  condicoes_pagamento text,
  exclusoes_ambito text,
  prazo_validade date,
  outras_informacoes text,
  nota_primeline text,
  criado_em timestamptz not null default now(),
  unique (mapa_id, fornecedor_id)
);

create table if not exists public.comparativo_itens (
  id uuid primary key default gen_random_uuid(),
  mapa_id uuid not null references public.mapas_comparativos(id) on delete cascade,
  numero text not null,
  designacao text not null check (btrim(designacao) <> ''),
  unidade text not null default 'un',
  quantidade numeric not null check (quantidade > 0),
  criado_em timestamptz not null default now(),
  unique (mapa_id, numero)
);

create table if not exists public.comparativo_itens_precos (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.comparativo_itens(id) on delete cascade,
  proposta_id uuid not null references public.comparativo_propostas(id) on delete cascade,
  preco_unitario numeric not null check (preco_unitario >= 0),
  preco_total numeric not null check (preco_total >= 0),
  observacoes text,
  criado_em timestamptz not null default now(),
  unique (item_id, proposta_id)
);

create table if not exists public.comparativo_ajustes (
  id uuid primary key default gen_random_uuid(),
  mapa_id uuid not null references public.mapas_comparativos(id) on delete cascade,
  proposta_id uuid not null references public.comparativo_propostas(id) on delete cascade,
  valor_ajustado numeric not null,
  justificacao text not null check (btrim(justificacao) <> ''),
  criado_em timestamptz not null default now()
);

create index if not exists mapas_comparativos_obra_idx on public.mapas_comparativos(obra_id, criado_em desc);
create index if not exists comparativo_propostas_mapa_idx on public.comparativo_propostas(mapa_id);
create index if not exists comparativo_itens_mapa_idx on public.comparativo_itens(mapa_id);
create index if not exists comparativo_precos_item_idx on public.comparativo_itens_precos(item_id);
create index if not exists comparativo_ajustes_mapa_idx on public.comparativo_ajustes(mapa_id);

create or replace function public.fn_atualizar_melhor_preco_comparativo(p_mapa_id uuid)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_total numeric;
begin
  select coalesce(sum(melhor), 0) into v_total
  from (
    select min(p.preco_total) as melhor
    from public.comparativo_itens i
    join public.comparativo_itens_precos p on p.item_id=i.id
    where i.mapa_id=p_mapa_id
    group by i.id
  ) menores;
  update public.mapas_comparativos
  set melhor_preco_comparativo=v_total, atualizado_em=now()
  where id=p_mapa_id;
  return v_total;
end $$;

create or replace function public.fn_calcular_preco_item_comparativo()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_quantidade numeric; v_mapa_item uuid; v_mapa_proposta uuid;
begin
  select mapa_id,quantidade into v_mapa_item,v_quantidade
  from public.comparativo_itens where id=new.item_id;
  select mapa_id into v_mapa_proposta
  from public.comparativo_propostas where id=new.proposta_id;
  if v_mapa_item is null or v_mapa_item is distinct from v_mapa_proposta then
    raise exception 'O item e a proposta devem pertencer ao mesmo mapa comparativo.' using errcode='23514';
  end if;
  new.preco_total:=round(new.preco_unitario*v_quantidade, 2);
  return new;
end $$;

create or replace function public.fn_recalcular_mapa_apos_preco()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_mapa uuid;
begin
  select mapa_id into v_mapa from public.comparativo_itens
  where id=case when tg_op='DELETE' then old.item_id else new.item_id end;
  perform public.fn_atualizar_melhor_preco_comparativo(v_mapa);
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;

create or replace function public.fn_recalcular_precos_quantidade()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.comparativo_itens_precos
  set preco_total=round(preco_unitario*new.quantidade,2)
  where item_id=new.id;
  perform public.fn_atualizar_melhor_preco_comparativo(new.mapa_id);
  return new;
end $$;

drop trigger if exists trg_calcular_preco_item_comparativo on public.comparativo_itens_precos;
create trigger trg_calcular_preco_item_comparativo before insert or update of item_id,proposta_id,preco_unitario
on public.comparativo_itens_precos for each row execute function public.fn_calcular_preco_item_comparativo();
drop trigger if exists trg_recalcular_mapa_apos_preco on public.comparativo_itens_precos;
create trigger trg_recalcular_mapa_apos_preco after insert or update or delete
on public.comparativo_itens_precos for each row execute function public.fn_recalcular_mapa_apos_preco();
drop trigger if exists trg_recalcular_precos_quantidade on public.comparativo_itens;
create trigger trg_recalcular_precos_quantidade after update of quantidade
on public.comparativo_itens for each row execute function public.fn_recalcular_precos_quantidade();

create or replace function public.fn_resumo_mapa_comparativo(p_mapa_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_mapa public.mapas_comparativos; v_melhores jsonb; v_itens_sem_cotacao integer;
begin
  select * into v_mapa from public.mapas_comparativos where id=p_mapa_id;
  if not found then raise exception 'Mapa comparativo não encontrado.' using errcode='P0002'; end if;
  if not public.fn_pode_ver_obra(v_mapa.obra_id) then raise exception 'Sem acesso a esta obra.' using errcode='42501'; end if;

  with classificados as (
    select i.id item_id,i.numero,i.designacao,p.preco_total,pr.fornecedor_id,f.nome fornecedor,
      row_number() over(partition by i.id order by p.preco_total,pr.id) posicao
    from public.comparativo_itens i
    join public.comparativo_itens_precos p on p.item_id=i.id
    join public.comparativo_propostas pr on pr.id=p.proposta_id
    join public.fornecedores f on f.id=pr.fornecedor_id
    where i.mapa_id=p_mapa_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('item_id',item_id,'numero',numero,'designacao',designacao,
    'fornecedor_id',fornecedor_id,'fornecedor',fornecedor,'melhor_preco',preco_total) order by numero),'[]'::jsonb)
  into v_melhores from classificados where posicao=1;

  select count(*) into v_itens_sem_cotacao from public.comparativo_itens i
  where i.mapa_id=p_mapa_id and not exists(select 1 from public.comparativo_itens_precos p where p.item_id=i.id);

  return jsonb_build_object(
    'mapa',to_jsonb(v_mapa),
    'melhores_por_item',v_melhores,
    'itens_sem_cotacao',v_itens_sem_cotacao,
    'melhor_preco_comparativo',v_mapa.melhor_preco_comparativo,
    'diferenca_negociacao',v_mapa.diferenca_negociacao,
    'desvio_orcamento_valor',v_mapa.desvio_orcamento_valor,
    'desvio_orcamento_percentual',v_mapa.desvio_orcamento_percentual,
    'margem_real_valor',v_mapa.margem_real_valor,
    'margem_real_percentual',v_mapa.margem_real_percentual
  );
end $$;

alter table public.subempreitadas add column if not exists mapa_comparativo_id uuid references public.mapas_comparativos(id) on delete set null;
create unique index if not exists subempreitadas_mapa_comparativo_uidx
on public.subempreitadas(mapa_comparativo_id) where mapa_comparativo_id is not null;

create or replace function public.fn_criar_subempreitada_do_comparativo(
  p_mapa_id uuid,p_proposta_id uuid,p_fase_id uuid,p_data_inicio_prevista date,
  p_data_fim_prevista date,p_condicao_pagamento text default null
) returns public.subempreitadas language plpgsql security definer set search_path=public,pg_temp as $$
declare v_mapa public.mapas_comparativos; v_proposta public.comparativo_propostas; v_sub public.subempreitadas;
begin
  select * into v_mapa from public.mapas_comparativos where id=p_mapa_id for update;
  if not found then raise exception 'Mapa comparativo não encontrado.'; end if;
  if not public.fn_pode_editar_obra(v_mapa.obra_id) then raise exception 'Sem permissão para adjudicar nesta obra.' using errcode='42501'; end if;
  if exists(select 1 from public.subempreitadas where mapa_comparativo_id=p_mapa_id) then raise exception 'Este mapa já originou uma subempreitada.' using errcode='23505'; end if;
  if v_mapa.valor_adjudicado_real is null then raise exception 'Preencha o Valor Adjudicado Real antes de criar a subempreitada.' using errcode='23514'; end if;
  select * into v_proposta from public.comparativo_propostas where id=p_proposta_id and mapa_id=p_mapa_id;
  if not found then raise exception 'A proposta não pertence a este mapa.' using errcode='23514'; end if;
  if not exists(select 1 from public.fases where id=p_fase_id and obra_id=v_mapa.obra_id) then raise exception 'A fase não pertence a esta obra.' using errcode='23514'; end if;
  insert into public.subempreitadas(obra_id,fase_id,fornecedor_id,especialidade,valor_adjudicado,estado,
    data_inicio_prevista,data_fim_prevista,condicao_pagamento,mapa_comparativo_id)
  values(v_mapa.obra_id,p_fase_id,v_proposta.fornecedor_id,v_mapa.especialidade,v_mapa.valor_adjudicado_real,
    'em_execucao',p_data_inicio_prevista,p_data_fim_prevista,p_condicao_pagamento,p_mapa_id)
  returning * into v_sub;
  return v_sub;
end $$;

alter table public.mapas_comparativos enable row level security;
alter table public.comparativo_propostas enable row level security;
alter table public.comparativo_itens enable row level security;
alter table public.comparativo_itens_precos enable row level security;
alter table public.comparativo_ajustes enable row level security;

drop policy if exists mapas_comparativos_select on public.mapas_comparativos;
create policy mapas_comparativos_select on public.mapas_comparativos for select to authenticated using(public.fn_pode_ver_obra(obra_id));
drop policy if exists mapas_comparativos_write on public.mapas_comparativos;
create policy mapas_comparativos_write on public.mapas_comparativos for all to authenticated
using(public.fn_pode_editar_obra(obra_id)) with check(public.fn_pode_editar_obra(obra_id));

do $$ declare t text; parent_expr text; begin
  foreach t in array array['comparativo_propostas','comparativo_itens','comparativo_ajustes'] loop
    execute format('drop policy if exists %I_select on public.%I',t,t);
    execute format('create policy %I_select on public.%I for select to authenticated using(exists(select 1 from public.mapas_comparativos m where m.id=mapa_id and public.fn_pode_ver_obra(m.obra_id)))',t,t);
    execute format('drop policy if exists %I_write on public.%I',t,t);
    execute format('create policy %I_write on public.%I for all to authenticated using(exists(select 1 from public.mapas_comparativos m where m.id=mapa_id and public.fn_pode_editar_obra(m.obra_id))) with check(exists(select 1 from public.mapas_comparativos m where m.id=mapa_id and public.fn_pode_editar_obra(m.obra_id)))',t,t);
  end loop;
end $$;

drop policy if exists comparativo_itens_precos_select on public.comparativo_itens_precos;
create policy comparativo_itens_precos_select on public.comparativo_itens_precos for select to authenticated using(exists(
  select 1 from public.comparativo_itens i join public.mapas_comparativos m on m.id=i.mapa_id
  where i.id=item_id and public.fn_pode_ver_obra(m.obra_id)));
drop policy if exists comparativo_itens_precos_write on public.comparativo_itens_precos;
create policy comparativo_itens_precos_write on public.comparativo_itens_precos for all to authenticated using(exists(
  select 1 from public.comparativo_itens i join public.mapas_comparativos m on m.id=i.mapa_id
  where i.id=item_id and public.fn_pode_editar_obra(m.obra_id))) with check(exists(
  select 1 from public.comparativo_itens i join public.mapas_comparativos m on m.id=i.mapa_id
  where i.id=item_id and public.fn_pode_editar_obra(m.obra_id)));

grant select,insert,update,delete on public.mapas_comparativos,public.comparativo_propostas,
  public.comparativo_itens,public.comparativo_itens_precos,public.comparativo_ajustes to authenticated;
revoke all on function public.fn_resumo_mapa_comparativo(uuid) from public,anon;
revoke all on function public.fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text) from public,anon;
grant execute on function public.fn_resumo_mapa_comparativo(uuid) to authenticated;
grant execute on function public.fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text) to authenticated;

commit;

select
  to_regclass('public.mapas_comparativos') is not null as mapas,
  to_regclass('public.comparativo_propostas') is not null as propostas,
  to_regclass('public.comparativo_itens') is not null as itens,
  to_regclass('public.comparativo_itens_precos') is not null as precos,
  to_regclass('public.comparativo_ajustes') is not null as ajustes,
  to_regprocedure('public.fn_resumo_mapa_comparativo(uuid)') is not null as rpc_resumo;
