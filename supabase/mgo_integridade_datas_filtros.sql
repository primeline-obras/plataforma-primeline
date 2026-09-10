-- PRIMELINE GO | MGO: não inventar datas de pagamento.
-- O filtro de obras históricas é tratado no frontend; este aditivo corrige a RPC.
begin;

create or replace function public.fn_mapa_gestao_obras_excel()
returns table (
  origem_id uuid, obra_id uuid, obra_numero text, obra_nome text,
  categoria text, data_lancamento date, entidade_nome text, descricao text,
  documento text, unidade_medida text, quantidade numeric,
  valor_unitario numeric, data_pagamento date, valor numeric
)
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  base record;
  dados jsonb;
  origem regclass;
begin
  if not public.fn_pode_ver_mapa_gestao_obras() then
    raise exception 'Sem acesso ao Mapa de Gestão de Obras.' using errcode='42501';
  end if;

  for base in select * from public.fn_mapa_gestao_obras()
  loop
    dados := '{}'::jsonb;
    origem := case base.categoria
      when 'materiais' then to_regclass('public.lancamentos_materiais')
      when 'estaleiro' then to_regclass('public.despesas_estaleiro')
      when 'mao_obra' then to_regclass('public.lancamentos_mao_obra')
      when 'subempreitadas' then to_regclass('public.pagamentos_subempreitada')
      when 'faturacao' then to_regclass('public.faturacao')
      else null end;
    if origem is not null then
      execute format('select to_jsonb(t) from %s t where id=$1',origem)
        into dados using base.origem_id;
      dados := coalesce(dados,'{}'::jsonb);
    end if;

    origem_id:=base.origem_id; obra_id:=base.obra_id; obra_numero:=base.obra_numero;
    obra_nome:=base.obra_nome; categoria:=base.categoria; data_lancamento:=base.data_lancamento;
    entidade_nome:=base.entidade_nome; descricao:=base.descricao; documento:=base.documento;
    unidade_medida:=coalesce(nullif(dados->>'unidade_medida',''),nullif(dados->>'unidade',''),
      case when base.categoria='mao_obra' then 'h' end);
    quantidade:=coalesce(nullif(dados->>'quantidade','')::numeric,nullif(dados->>'horas','')::numeric);
    valor_unitario:=coalesce(nullif(dados->>'valor_unitario','')::numeric,nullif(dados->>'valor_hora','')::numeric);
    data_pagamento:=nullif(left(dados->>'data_pagamento',10),'')::date;
    valor:=base.valor;
    return next;
  end loop;
end $$;

revoke all on function public.fn_mapa_gestao_obras_excel() from public,anon;
grant execute on function public.fn_mapa_gestao_obras_excel() to authenticated;

commit;

select
  to_regprocedure('public.fn_mapa_gestao_obras_excel()') is not null as rpc_excel_ativa,
  pg_get_functiondef('public.fn_mapa_gestao_obras_excel()'::regprocedure)
    not ilike '%data_pagamento := COALESCE%' as sem_data_pagamento_inventada;
