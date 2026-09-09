-- TESTE REAL E REVERSÍVEL: cria um item, uma proposta, um preço e um ajuste,
-- testa as duas cascatas e termina com ROLLBACK. Não deixa dados de teste.

begin;

create temporary table teste_cascata_comparativo (
  teste text,
  precos_antes integer,
  ajustes_antes integer,
  precos_depois integer,
  ajustes_depois integer,
  resultado text
) on commit drop;

do $$
declare
  v_obra_id uuid;
  v_fornecedor_id uuid;
  v_mapa_id uuid;
  v_item_id uuid;
  v_proposta_id uuid;
  v_precos_antes integer;
  v_ajustes_antes integer;
  v_precos_depois integer;
  v_ajustes_depois integer;
begin
  select id into v_obra_id from public.obras limit 1;
  select id into v_fornecedor_id from public.fornecedores order by nome limit 1;
  if v_obra_id is null or v_fornecedor_id is null then
    raise exception 'O teste precisa de pelo menos uma obra e um fornecedor existentes.';
  end if;

  insert into public.mapas_comparativos (obra_id, especialidade, descricao)
  values (v_obra_id, '__TESTE_CASCATA__', 'Teste reversível de edição/eliminação') returning id into v_mapa_id;
  insert into public.comparativo_itens (mapa_id, numero, designacao, unidade, quantidade)
  values (v_mapa_id, '__1__', 'Item temporário com ajuste de escopo', 'un', 2) returning id into v_item_id;
  insert into public.comparativo_propostas (mapa_id, fornecedor_id, data_proposta)
  values (v_mapa_id, v_fornecedor_id, current_date) returning id into v_proposta_id;
  insert into public.comparativo_itens_precos (item_id, proposta_id, preco_unitario)
  values (v_item_id, v_proposta_id, 12.50);
  insert into public.comparativo_ajustes (mapa_id, proposta_id, valor_ajustado, justificacao)
  values (v_mapa_id, v_proposta_id, 20, 'Ajuste de escopo temporário para provar a cascata');

  select count(*) into v_precos_antes from public.comparativo_itens_precos where proposta_id = v_proposta_id;
  select count(*) into v_ajustes_antes from public.comparativo_ajustes where proposta_id = v_proposta_id;
  delete from public.comparativo_propostas where id = v_proposta_id;
  select count(*) into v_precos_depois from public.comparativo_itens_precos where proposta_id = v_proposta_id;
  select count(*) into v_ajustes_depois from public.comparativo_ajustes where proposta_id = v_proposta_id;
  if v_precos_depois <> 0 or v_ajustes_depois <> 0 then raise exception 'Falha na cascata da proposta.'; end if;
  insert into teste_cascata_comparativo values ('ELIMINAR PROPOSTA COM AJUSTE', v_precos_antes, v_ajustes_antes, v_precos_depois, v_ajustes_depois, 'OK');

  insert into public.comparativo_propostas (mapa_id, fornecedor_id, data_proposta)
  values (v_mapa_id, v_fornecedor_id, current_date) returning id into v_proposta_id;
  insert into public.comparativo_itens_precos (item_id, proposta_id, preco_unitario)
  values (v_item_id, v_proposta_id, 15);
  select count(*) into v_precos_antes from public.comparativo_itens_precos where item_id = v_item_id;
  delete from public.comparativo_itens where id = v_item_id;
  select count(*) into v_precos_depois from public.comparativo_itens_precos where item_id = v_item_id;
  if v_precos_depois <> 0 then raise exception 'Falha na cascata do item.'; end if;
  insert into teste_cascata_comparativo values ('ELIMINAR ITEM COM PREÇO', v_precos_antes, 0, v_precos_depois, 0, 'OK');
end;
$$;

select * from teste_cascata_comparativo order by teste;

rollback;
