-- PRIMELINE GO | Importação assistida de propostas PDF no mapa comparativo
-- Aplicar depois de mapa_comparativo_dinamico.sql.
begin;

alter table public.comparativo_propostas
  add column if not exists fornecedor_nome_extraido text,
  add column if not exists referencia_proposta text,
  add column if not exists total_original numeric,
  add column if not exists documento_url text,
  add column if not exists documento_nome text,
  add column if not exists extracao_dados jsonb not null default '{}'::jsonb,
  add column if not exists estado_revisao text not null default 'revisto',
  add column if not exists prazo_entrega text,
  add column if not exists prazo_montagem text,
  add column if not exists garantia text,
  add column if not exists validade_dias integer;

alter table public.comparativo_propostas drop constraint if exists comparativo_propostas_total_original_check;
alter table public.comparativo_propostas add constraint comparativo_propostas_total_original_check
  check (total_original is null or total_original >= 0);
alter table public.comparativo_propostas drop constraint if exists comparativo_propostas_estado_revisao_check;
alter table public.comparativo_propostas add constraint comparativo_propostas_estado_revisao_check
  check (estado_revisao in ('por_rever','revisto','requer_esclarecimento'));
alter table public.comparativo_propostas drop constraint if exists comparativo_propostas_validade_dias_check;
alter table public.comparativo_propostas add constraint comparativo_propostas_validade_dias_check
  check (validade_dias is null or validade_dias between 0 and 3650);

alter table public.comparativo_itens_precos
  add column if not exists descricao_original text,
  add column if not exists quantidade_original numeric,
  add column if not exists unidade_original text,
  add column if not exists preco_total_original numeric,
  add column if not exists estado_ambito text not null default 'incluido',
  add column if not exists comparavel boolean not null default true,
  add column if not exists origem_pagina integer,
  add column if not exists confianca_extracao numeric;

alter table public.comparativo_itens_precos drop constraint if exists comparativo_precos_estado_ambito_check;
alter table public.comparativo_itens_precos add constraint comparativo_precos_estado_ambito_check
  check (estado_ambito in ('incluido','excluido','parcial','alternativa','nao_cotado'));
alter table public.comparativo_itens_precos drop constraint if exists comparativo_precos_quantidade_original_check;
alter table public.comparativo_itens_precos add constraint comparativo_precos_quantidade_original_check
  check (quantidade_original is null or quantidade_original >= 0);
alter table public.comparativo_itens_precos drop constraint if exists comparativo_precos_total_original_check;
alter table public.comparativo_itens_precos add constraint comparativo_precos_total_original_check
  check (preco_total_original is null or preco_total_original >= 0);
alter table public.comparativo_itens_precos drop constraint if exists comparativo_precos_confianca_check;
alter table public.comparativo_itens_precos add constraint comparativo_precos_confianca_check
  check (confianca_extracao is null or confianca_extracao between 0 and 1);

create or replace function public.fn_atualizar_melhor_preco_comparativo(p_mapa_id uuid)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_total numeric;
begin
  select coalesce(sum(melhor), 0) into v_total
  from (
    select min(p.preco_total) as melhor
    from public.comparativo_itens i
    join public.comparativo_itens_precos p on p.item_id=i.id
    where i.mapa_id=p_mapa_id and p.comparavel and p.estado_ambito='incluido'
    group by i.id
  ) menores;
  update public.mapas_comparativos
  set melhor_preco_comparativo=v_total, atualizado_em=now()
  where id=p_mapa_id;
  return v_total;
end $$;

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
    join public.comparativo_itens_precos p on p.item_id=i.id and p.comparavel and p.estado_ambito='incluido'
    join public.comparativo_propostas pr on pr.id=p.proposta_id
    join public.fornecedores f on f.id=pr.fornecedor_id where i.mapa_id=p_mapa_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('item_id',item_id,'numero',numero,'designacao',designacao,
    'fornecedor_id',fornecedor_id,'fornecedor',fornecedor,'melhor_preco',preco_total) order by numero),'[]'::jsonb)
  into v_melhores from classificados where posicao=1;
  select count(*) into v_itens_sem_cotacao from public.comparativo_itens i where i.mapa_id=p_mapa_id
    and not exists(select 1 from public.comparativo_itens_precos p where p.item_id=i.id and p.comparavel and p.estado_ambito='incluido');
  return jsonb_build_object('mapa',to_jsonb(v_mapa),'melhores_por_item',v_melhores,
    'itens_sem_cotacao',v_itens_sem_cotacao,'melhor_preco_comparativo',v_mapa.melhor_preco_comparativo,
    'diferenca_negociacao',v_mapa.diferenca_negociacao,'desvio_orcamento_valor',v_mapa.desvio_orcamento_valor,
    'desvio_orcamento_percentual',v_mapa.desvio_orcamento_percentual,'margem_real_valor',v_mapa.margem_real_valor,
    'margem_real_percentual',v_mapa.margem_real_percentual);
end $$;

create or replace function public.fn_criar_fornecedor_comparativo(p_mapa_id uuid, p_nome text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_obra_id uuid; v_empresa_id uuid; v_nome text; v_chave text; v_fornecedor public.fornecedores; v_ja_existia boolean := false;
begin
  v_nome := regexp_replace(btrim(coalesce(p_nome,'')), '\s+', ' ', 'g');
  if length(v_nome) < 2 then raise exception 'Indique o nome do fornecedor.' using errcode='23514'; end if;
  v_chave := lower(regexp_replace(regexp_replace(v_nome,'\y(unipessoal|unip|lda|sa|ltda)\y\.?','','gi'),'[^[:alnum:]]+','','g'));

  select m.obra_id,o.empresa_id into v_obra_id,v_empresa_id
  from public.mapas_comparativos m join public.obras o on o.id=m.obra_id where m.id=p_mapa_id;
  if v_obra_id is null then raise exception 'Mapa comparativo não encontrado.' using errcode='P0002'; end if;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Sem permissão para criar fornecedores nesta obra.' using errcode='42501';
  end if;

  select * into v_fornecedor from public.fornecedores
  where empresa_id=v_empresa_id
    and lower(regexp_replace(regexp_replace(nome,'\y(unipessoal|unip|lda|sa|ltda)\y\.?','','gi'),'[^[:alnum:]]+','','g'))=v_chave
  order by id limit 1;
  if found then
    v_ja_existia := true;
  else
    insert into public.fornecedores(empresa_id,nome,tipo_entidade,estado_confianca)
    values(v_empresa_id,v_nome,'subempreiteiro','nao_avaliado') returning * into v_fornecedor;
  end if;

  return jsonb_build_object('id',v_fornecedor.id,'nome',v_fornecedor.nome,
    'tipo_entidade',v_fornecedor.tipo_entidade,'estado_confianca',v_fornecedor.estado_confianca,
    'ja_existia',v_ja_existia);
end $$;

create or replace function public.fn_importar_proposta_comparativo(
  p_mapa_id uuid, p_fornecedor_id uuid, p_dados jsonb, p_linhas jsonb
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_obra_id uuid; v_empresa_id uuid; v_proposta_id uuid; v_linha jsonb; v_item_id uuid;
  v_numero text; v_quantidade numeric; v_unitario numeric; v_total_original numeric;
  v_criados integer := 0; v_existente integer;
begin
  select m.obra_id,o.empresa_id into v_obra_id,v_empresa_id
  from public.mapas_comparativos m join public.obras o on o.id=m.obra_id where m.id=p_mapa_id;
  if v_obra_id is null then raise exception 'Mapa comparativo não encontrado.' using errcode='P0002'; end if;
  if not public.fn_pode_editar_obra(v_obra_id) then raise exception 'Sem permissão para importar nesta obra.' using errcode='42501'; end if;
  if not exists(select 1 from public.fornecedores where id=p_fornecedor_id and empresa_id=v_empresa_id) then
    raise exception 'O fornecedor não pertence à empresa desta obra.' using errcode='23514';
  end if;
  if jsonb_typeof(coalesce(p_linhas,'[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_linhas,'[]'::jsonb))=0 then
    raise exception 'Selecione pelo menos uma linha da proposta.' using errcode='23514';
  end if;
  select count(*) into v_existente from public.comparativo_propostas where mapa_id=p_mapa_id and fornecedor_id=p_fornecedor_id;
  if v_existente>0 then raise exception 'Este fornecedor já tem uma proposta neste mapa. Edite a proposta existente.' using errcode='23505'; end if;

  insert into public.comparativo_propostas(
    mapa_id,fornecedor_id,data_proposta,prazo_validade,condicoes_pagamento,exclusoes_ambito,
    fornecedor_nome_extraido,referencia_proposta,total_original,documento_url,documento_nome,extracao_dados,
    estado_revisao,prazo_entrega,prazo_montagem,garantia,validade_dias,outras_informacoes
  ) values (
    p_mapa_id,p_fornecedor_id,nullif(p_dados->>'proposalDate','')::date,nullif(p_dados->>'validityDate','')::date,
    nullif(p_dados->>'paymentTerms',''),nullif(p_dados->>'exclusions',''),nullif(p_dados->>'supplierName',''),
    nullif(p_dados->>'reference',''),nullif(p_dados->>'officialTotal','')::numeric,nullif(p_dados->>'documentPath',''),nullif(p_dados->>'documentName',''),
    coalesce(p_dados,'{}'::jsonb) - 'fullText' - 'lines','revisto',nullif(p_dados->>'deliveryTerms',''),
    nullif(p_dados->>'assemblyTerms',''),nullif(p_dados->>'warranty',''),nullif(p_dados->>'validityDays','')::integer,
    nullif(p_dados->>'reviewNotes','')
  ) returning id into v_proposta_id;

  for v_linha in select value from jsonb_array_elements(p_linhas) loop
    v_item_id := nullif(v_linha->>'itemId','')::uuid;
    if v_item_id is not null and not exists(select 1 from public.comparativo_itens where id=v_item_id and mapa_id=p_mapa_id) then
      raise exception 'Um dos itens selecionados não pertence a este mapa.' using errcode='23514';
    end if;
    v_quantidade := greatest(coalesce(nullif(v_linha->>'normalizedQuantity','')::numeric,1),0.0001);
    v_total_original := nullif(v_linha->>'originalTotal','')::numeric;
    v_unitario := nullif(v_linha->>'unitPrice','')::numeric;
    if v_unitario is null and v_total_original is not null then v_unitario := round(v_total_original/v_quantidade,4); end if;
    if v_unitario is null or v_unitario<0 then raise exception 'Todas as linhas selecionadas precisam de valor.' using errcode='23514'; end if;

    if v_item_id is null then
      v_numero := nullif(btrim(v_linha->>'number'),'');
      if v_numero is null then
        select 'PDF-'||(count(*)+1)::text into v_numero from public.comparativo_itens where mapa_id=p_mapa_id;
      end if;
      while exists(select 1 from public.comparativo_itens where mapa_id=p_mapa_id and numero=v_numero) loop
        v_numero := v_numero||'-'||(v_criados+1)::text;
      end loop;
      insert into public.comparativo_itens(mapa_id,numero,designacao,unidade,quantidade)
      values(p_mapa_id,v_numero,coalesce(nullif(btrim(v_linha->>'normalizedDescription'),''),'Item importado'),
        coalesce(nullif(btrim(v_linha->>'unit'),''),'un'),v_quantidade) returning id into v_item_id;
    end if;

    insert into public.comparativo_itens_precos(
      item_id,proposta_id,preco_unitario,observacoes,descricao_original,quantidade_original,
      unidade_original,preco_total_original,estado_ambito,comparavel,origem_pagina,confianca_extracao
    ) values (
      v_item_id,v_proposta_id,v_unitario,nullif(v_linha->>'notes',''),nullif(v_linha->>'originalDescription',''),
      nullif(v_linha->>'originalQuantity','')::numeric,nullif(v_linha->>'originalUnit',''),v_total_original,
      coalesce(nullif(v_linha->>'scopeStatus',''),'incluido'),coalesce((v_linha->>'comparable')::boolean,false),
      nullif(v_linha->>'sourcePage','')::integer,nullif(v_linha->>'confidence','')::numeric
    );
    v_criados := v_criados+1;
  end loop;

  return jsonb_build_object('proposta_id',v_proposta_id,'linhas_criadas',v_criados);
end $$;

revoke all on function public.fn_criar_fornecedor_comparativo(uuid,text) from public,anon;
revoke all on function public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.fn_criar_fornecedor_comparativo(uuid,text) to authenticated;
grant execute on function public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb) to authenticated;

-- Recalcula os mapas existentes segundo a regra de comparabilidade.
select public.fn_atualizar_melhor_preco_comparativo(id) from public.mapas_comparativos;

commit;

select
  to_regprocedure('public.fn_criar_fornecedor_comparativo(uuid,text)') is not null as cadastro_fornecedor_controlado,
  to_regprocedure('public.fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)') is not null as importacao_pdf_atomica,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='comparativo_itens_precos' and column_name='comparavel') as melhor_preco_com_ambito;
