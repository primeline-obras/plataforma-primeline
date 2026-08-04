-- PRIMELINE | Criar obra nova a partir da estrutura de uma obra-modelo.
-- Não copia responsáveis, contratos, investimentos, valores, tarefas, documentos,
-- fornecedores, subempreitadas, faturas, pagamentos nem execução realizada.

begin;

create or replace function public.fn_criar_obra_de_modelo(
  p_modelo_obra_id uuid,
  p_numero text,
  p_nome text,
  p_cliente text default null,
  p_morada text default null,
  p_tipo text default null,
  p_modalidade text default null,
  p_diretor_obra_id uuid default null,
  p_situacao text default 'planeamento',
  p_data_inicio date default null,
  p_data_fim_prevista date default null,
  p_copiar_orcamento boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_obra public.obras%rowtype;
  v_fase record;
  v_fase_nova_id uuid;
  v_total_fases integer := 0;
  v_total_itens integer := 0;
  v_itens_inseridos integer := 0;
  v_colunas_itens text;
begin
  if not public.fn_e_admin() then
    raise exception 'A criação de obras por modelo está reservada à Gerência.';
  end if;

  if p_modelo_obra_id is null or not exists (
    select 1 from public.obras where id = p_modelo_obra_id
  ) then
    raise exception 'A obra-modelo selecionada não existe.';
  end if;

  if nullif(btrim(p_numero), '') is null or nullif(btrim(p_nome), '') is null then
    raise exception 'Número e designação da nova obra são obrigatórios.';
  end if;

  if p_data_inicio is not null and p_data_fim_prevista is not null
     and p_data_fim_prevista < p_data_inicio then
    raise exception 'A data de fim prevista não pode ser anterior à data de início.';
  end if;

  if exists (
    select 1 from public.obras
    where empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid
      and lower(btrim(numero::text)) = lower(btrim(p_numero))
  ) then
    raise exception 'Já existe uma obra com este número.';
  end if;

  insert into public.obras (
    empresa_id, numero, nome, cliente, morada, tipo, modalidade,
    diretor_obra_id, situacao, data_inicio, data_fim_prevista
  ) values (
    '73fb13c8-d29f-4192-a506-4ca243343add'::uuid,
    btrim(p_numero), btrim(p_nome), nullif(btrim(p_cliente), ''),
    nullif(btrim(p_morada), ''), nullif(btrim(p_tipo), ''),
    nullif(btrim(p_modalidade), ''), p_diretor_obra_id,
    coalesce(nullif(btrim(p_situacao), ''), 'planeamento'),
    p_data_inicio, p_data_fim_prevista
  ) returning * into v_obra;

  -- Apenas campos descritivos são elegíveis para copiar do orçamento.
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_colunas_itens
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'itens_orcamento'
    and c.column_name = any(array[
      'codigo', 'descricao', 'designacao', 'unidade', 'categoria',
      'especialidade', 'capitulo', 'subcapitulo', 'ordem'
    ]);

  for v_fase in
    select id, codigo, descricao
    from public.fases
    where obra_id = p_modelo_obra_id
    order by codigo, descricao
  loop
    v_fase_nova_id := gen_random_uuid();
    insert into public.fases (id, obra_id, codigo, descricao)
    values (v_fase_nova_id, v_obra.id, v_fase.codigo, v_fase.descricao);
    v_total_fases := v_total_fases + 1;

    if to_regclass('public.planeamento_fases_resumo') is not null
       and exists (select 1 from public.planeamento_fases_resumo where fase_id = v_fase.id) then
      insert into public.planeamento_fases_resumo (fase_id)
      values (v_fase_nova_id);
    end if;

    if coalesce(p_copiar_orcamento, true) and v_colunas_itens is not null then
      execute format(
        'insert into public.itens_orcamento (id, fase_id, %1$s) '
        'select gen_random_uuid(), $1, %1$s from public.itens_orcamento where fase_id = $2',
        v_colunas_itens
      ) using v_fase_nova_id, v_fase.id;
      get diagnostics v_itens_inseridos = row_count;
      v_total_itens := v_total_itens + v_itens_inseridos;
    end if;
  end loop;

  return jsonb_build_object(
    'obra', to_jsonb(v_obra),
    'fases_copiadas', v_total_fases,
    'itens_orcamento_copiados', v_total_itens
  );
end;
$$;

revoke all on function public.fn_criar_obra_de_modelo(
  uuid, text, text, text, text, text, text, uuid, text, date, date, boolean
) from public, anon;
grant execute on function public.fn_criar_obra_de_modelo(
  uuid, text, text, text, text, text, text, uuid, text, date, date, boolean
) to authenticated;

commit;

select
  count(*) as rpc_modelo_disponivel
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fn_criar_obra_de_modelo';
