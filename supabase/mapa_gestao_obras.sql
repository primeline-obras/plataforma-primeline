-- PRIMELINE | Mapa de Gestão de Obras — lançamentos pagos detalhados
begin;

create or replace function public.fn_mapa_gestao_obras()
returns table (
  origem_id uuid,
  obra_id uuid,
  obra_numero text,
  obra_nome text,
  categoria text,
  data_lancamento date,
  entidade_nome text,
  descricao text,
  documento text,
  valor numeric
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_atual public.utilizadores;
  v_linha record;
  v_json jsonb;
  v_obra public.obras;
  v_sub public.subempreitadas;
  v_uuid uuid;
  v_nome text;
  v_data_text text;
  v_estado text;
begin
  if not (public.fn_e_admin() or public.fn_e_financeiro()) then
    raise exception 'O Mapa de Gestão de Obras está reservado à Gerência e ao Financeiro.';
  end if;

  select * into v_atual
  from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id()
    and coalesce(u.ativo, true);

  if not found then
    raise exception 'Utilizador autenticado sem perfil ativo.';
  end if;

  -- Materiais: usa lancamentos_materiais quando a tabela existe.
  if to_regclass('public.lancamentos_materiais') is not null then
    for v_linha in execute 'select to_jsonb(t) as dados from public.lancamentos_materiais t'
    loop
      v_json := v_linha.dados;
      v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
      if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
      if v_json ? 'pago' and lower(coalesce(v_json ->> 'pago', 'false')) not in ('true', 't', '1') then continue; end if;
      if v_json ? 'data_pagamento' and nullif(v_json ->> 'data_pagamento', '') is null then continue; end if;

      begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
      select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id;
      if not found then continue; end if;

      v_nome := null;
      begin
        v_uuid := nullif(v_json ->> 'fornecedor_id', '')::uuid;
        select f.nome into v_nome from public.fornecedores f where f.id = v_uuid;
      exception when others then v_nome := null; end;
      v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'data_fatura',''), nullif(v_json ->> 'criado_em',''));

      origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome;
      categoria := 'materiais'; data_lancamento := left(v_data_text, 10)::date; entidade_nome := coalesce(v_nome, v_json ->> 'fornecedor', 'Fornecedor não identificado');
      descricao := coalesce(v_json ->> 'designacao', v_json ->> 'descricao', 'Material'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
      valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, nullif(v_json ->> 'valor','')::numeric, nullif(v_json ->> 'total','')::numeric, 0); return next;
    end loop;
  else
    -- Compatibilidade com o fluxo atual, que regista materiais em faturas.
    for v_linha in
      select f.*, o.numero as numero_obra, o.nome as nome_obra, fr.nome as nome_fornecedor
      from public.faturas f
      join public.obras o on o.id = f.obra_id
      left join public.fornecedores fr on fr.id = f.fornecedor_id
      where o.empresa_id = v_atual.empresa_id
        and f.tipo_origem = 'material'
        and f.estado_pagamento = 'pago'
    loop
      origem_id := v_linha.id; obra_id := v_linha.obra_id; obra_numero := v_linha.numero_obra::text; obra_nome := v_linha.nome_obra;
      categoria := 'materiais'; data_lancamento := v_linha.data_pagamento; entidade_nome := coalesce(v_linha.nome_fornecedor, 'Fornecedor não identificado');
      descricao := 'Fatura de material'; documento := v_linha.numero_doc; valor := coalesce(v_linha.valor, 0); return next;
    end loop;
  end if;

  -- Despesas de estaleiro.
  for v_linha in execute 'select to_jsonb(t) as dados from public.despesas_estaleiro t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    if nullif(v_json ->> 'estado_aprovacao','') is not null and lower(v_json ->> 'estado_aprovacao') not in ('aprovado','aprovada') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
    select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null;
    begin v_uuid := nullif(v_json ->> 'fornecedor_id', '')::uuid; select f.nome into v_nome from public.fornecedores f where f.id = v_uuid; exception when others then v_nome := null; end;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'estaleiro';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, v_json ->> 'fornecedor', 'Estaleiro');
    descricao := coalesce(v_json ->> 'designacao', v_json ->> 'descricao', 'Despesa de estaleiro'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
    valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, nullif(v_json ->> 'valor','')::numeric, 0); return next;
  end loop;

  -- Pessoal em obra / mão de obra: cada lançamento é custo realizado.
  for v_linha in execute 'select to_jsonb(t) as dados from public.lancamentos_mao_obra t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
    select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null;
    begin v_uuid := nullif(v_json ->> 'colaborador_id', '')::uuid; select c.nome into v_nome from public.colaboradores c where c.id = v_uuid; exception when others then v_nome := null; end;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'mao_obra';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, 'Colaborador não identificado');
    descricao := concat_ws(' · ', nullif(v_json ->> 'horas','') || case when nullif(v_json ->> 'horas','') is not null then ' h' end, nullif(v_json ->> 'percentual_afetacao','') || case when nullif(v_json ->> 'percentual_afetacao','') is not null then ' afetação' end);
    documento := null; valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, (nullif(v_json ->> 'horas','')::numeric * nullif(v_json ->> 'valor_hora','')::numeric), 0); return next;
  end loop;

  -- Pagamentos de subempreitadas.
  for v_linha in execute 'select to_jsonb(t) as dados from public.pagamentos_subempreitada t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    if nullif(v_json ->> 'estado_aprovacao','') is not null and lower(v_json ->> 'estado_aprovacao') not in ('aprovado','aprovada') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'subempreitada_id', '')::uuid; exception when others then continue; end;
    select * into v_sub from public.subempreitadas s where s.id = v_uuid; if not found then continue; end if;
    select * into v_obra from public.obras o where o.id = v_sub.obra_id and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null; select f.nome into v_nome from public.fornecedores f where f.id = v_sub.fornecedor_id;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'subempreitadas';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, 'Subempreiteiro não identificado');
    descricao := coalesce(v_sub.especialidade, v_json ->> 'descricao', 'Pagamento de subempreitada'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
    valor := coalesce(nullif(v_json ->> 'valor','')::numeric, nullif(v_json ->> 'valor_total','')::numeric, 0); return next;
  end loop;
end;
$function$;

revoke all on function public.fn_mapa_gestao_obras() from public, anon;
grant execute on function public.fn_mapa_gestao_obras() to authenticated;

commit;

select
  to_regprocedure('public.fn_mapa_gestao_obras()') is not null as rpc_mapa_gestao,
  to_regclass('public.lancamentos_materiais') is not null as tabela_lancamentos_materiais;
