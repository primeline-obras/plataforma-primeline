-- PRIMELINE | Parâmetros operacionais configuráveis.
-- Executar no SQL Editor do Supabase como owner.
-- Migração incremental: preserva valores já existentes e mantém os defaults atuais.

begin;

create table if not exists public.parametros_operacionais (
  chave text primary key,
  descricao text not null,
  valor text not null,
  atualizado_por uuid references public.utilizadores(id),
  atualizado_em timestamptz not null default now()
);

alter table public.parametros_operacionais
  add column if not exists chave text,
  add column if not exists descricao text,
  add column if not exists valor text,
  add column if not exists atualizado_por uuid references public.utilizadores(id),
  add column if not exists atualizado_em timestamptz not null default now();

create unique index if not exists parametros_operacionais_chave_key
  on public.parametros_operacionais (chave);

insert into public.parametros_operacionais (chave, descricao, valor)
values
  ('valor_minimo_contrato_subempreitada', 'Valor adjudicado a partir do qual é obrigatório contrato de subempreitada (€).', '5000'),
  ('antecedencias_alerta_contrato_rh', 'Antecedências dos alertas de fim de contrato de trabalho, em dias.', '60,45,30'),
  ('antecedencia_alerta_documento_colaborador', 'Antecedência do alerta de validade de documentos de colaboradores, em dias.', '30'),
  ('antecedencia_alerta_epi', 'Antecedência do alerta de validade de EPI, em dias.', '30'),
  ('antecedencia_alerta_medicina', 'Antecedência do alerta de Medicina do Trabalho, em dias.', '30'),
  ('antecedencia_alerta_viatura_inspecao', 'Antecedência do alerta de inspeção de viatura, em dias.', '15'),
  ('antecedencia_alerta_viatura_seguro', 'Antecedência do alerta de seguro de viatura, em dias.', '15'),
  ('antecedencias_alerta_documento_empresa', 'Antecedências dos alertas de documentos da empresa, em dias.', '15,7,3'),
  ('antecedencias_alerta_pedido_orcamento', 'Antecedências dos alertas de entrega de pedidos de orçamento, em dias.', '15,7,3'),
  ('antecedencia_alerta_reuniao_condominio', 'Antecedência do alerta de reunião de condomínio, em dias.', '7')
on conflict (chave) do nothing;

create or replace function public.fn_parametro_operacional_texto(
  p_chave text,
  p_default text
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select nullif(btrim(p.valor), '') from public.parametros_operacionais p where p.chave = p_chave),
    p_default
  );
$$;

create or replace function public.fn_parametro_operacional_numero(
  p_chave text,
  p_default numeric
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_valor text;
begin
  v_valor := public.fn_parametro_operacional_texto(p_chave, p_default::text);
  begin
    return replace(v_valor, ',', '.')::numeric;
  exception when invalid_text_representation then
    return p_default;
  end;
end;
$$;

create or replace function public.fn_parametro_operacional_dias(
  p_chave text,
  p_default integer[]
)
returns integer[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_texto text;
  v_dias integer[];
begin
  v_texto := public.fn_parametro_operacional_texto(p_chave, array_to_string(p_default, ','));
  select array_agg(x.dia order by x.ordem)
    into v_dias
  from (
    select btrim(parte) :: integer as dia, ordem
    from unnest(string_to_array(v_texto, ',')) with ordinality as partes(parte, ordem)
    where btrim(parte) ~ '^\d+$'
  ) x
  where x.dia >= 0;
  return coalesce(v_dias, p_default);
end;
$$;

revoke all on function public.fn_parametro_operacional_texto(text, text) from public, anon;
revoke all on function public.fn_parametro_operacional_numero(text, numeric) from public, anon;
revoke all on function public.fn_parametro_operacional_dias(text, integer[]) from public, anon;

create or replace function public.fn_validar_atualizacao_parametro_operacional()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.valor := btrim(new.valor);
  if new.chave in (
    'antecedencias_alerta_contrato_rh',
    'antecedencias_alerta_documento_empresa',
    'antecedencias_alerta_pedido_orcamento'
  ) and new.valor !~ '^\s*\d+\s*(,\s*\d+\s*)*$' then
    raise exception 'Indique uma lista de dias separada por vírgulas (ex.: 15,7,3).';
  end if;
  if new.chave like 'antecedencia_alerta_%'
     and new.chave not like 'antecedencias_%'
     and new.valor !~ '^\d+$' then
    raise exception 'A antecedência deve ser um número inteiro de dias.';
  end if;
  if new.chave = 'valor_minimo_contrato_subempreitada'
     and new.valor !~ '^\d+([\.,]\d+)?$' then
    raise exception 'O limite de contrato deve ser um valor numérico positivo.';
  end if;
  new.atualizado_por := public.fn_utilizador_atual_id();
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists trg_parametros_operacionais_atualizacao on public.parametros_operacionais;
create trigger trg_parametros_operacionais_atualizacao
before insert or update of valor on public.parametros_operacionais
for each row execute function public.fn_validar_atualizacao_parametro_operacional();

alter table public.parametros_operacionais enable row level security;
drop policy if exists parametros_operacionais_select_admin on public.parametros_operacionais;
create policy parametros_operacionais_select_admin
on public.parametros_operacionais for select to authenticated
using (public.fn_e_admin());
drop policy if exists parametros_operacionais_update_admin on public.parametros_operacionais;
create policy parametros_operacionais_update_admin
on public.parametros_operacionais for update to authenticated
using (public.fn_e_admin()) with check (public.fn_e_admin());

revoke all on public.parametros_operacionais from anon, authenticated;
grant select on public.parametros_operacionais to authenticated;
grant update (valor) on public.parametros_operacionais to authenticated;

-- Limite contratual, mantendo 5.000 € como fallback seguro.
create or replace function public.fn_limite_contrato_subempreitada()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_parametro_operacional_numero(
    'valor_minimo_contrato_subempreitada', 5000::numeric
  );
$$;
revoke all on function public.fn_limite_contrato_subempreitada() from public, anon;
grant execute on function public.fn_limite_contrato_subempreitada() to authenticated;

-- Contratos de trabalho: 60/45/30 por defeito.
create or replace function public.fn_verificar_alertas_fim_contrato()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_limiar integer;
  v_limites integer[] := public.fn_parametro_operacional_dias(
    'antecedencias_alerta_contrato_rh', array[60,45,30]
  );
begin
  for r in
    select cc.id, cc.data_fim_prevista, c.nome, c.empresa_id
    from public.colaboradores_contratos cc
    join public.colaboradores c on c.id = cc.colaborador_id and c.data_saida is null
    where cc.tipo_contrato = 'a_prazo'
      and cc.estado = 'ativo'
      and cc.data_fim_prevista is not null
  loop
    foreach v_limiar in array v_limites loop
      if r.data_fim_prevista - v_limiar = current_date then
        insert into public.alertas (
          empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
          data_evento_referencia, antecedencia_dias, data_gatilho,
          destinatario_role, estado
        ) values (
          r.empresa_id, 'fim_contrato_rh', 'colaboradores_contratos', r.id,
          'Contrato a prazo a terminar: ' || r.nome,
          'Fim previsto em ' || to_char(r.data_fim_prevista, 'DD/MM/YYYY')
            || ' (' || v_limiar || ' dias de antecedência)',
          r.data_fim_prevista, v_limiar, current_date, 'administrativo', 'pendente'
        ) on conflict do nothing;
      end if;
    end loop;
  end loop;
end;
$$;

-- Documentos, EPI, Medicina, inspeções e documentos da empresa.
create or replace function public.fn_verificar_alertas_vencimento()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inseridos integer := 0;
  v_parcial integer := 0;
  v_doc_colaborador integer := public.fn_parametro_operacional_numero('antecedencia_alerta_documento_colaborador', 30)::integer;
  v_epi integer := public.fn_parametro_operacional_numero('antecedencia_alerta_epi', 30)::integer;
  v_medicina integer := public.fn_parametro_operacional_numero('antecedencia_alerta_medicina', 30)::integer;
  v_inspecao integer := public.fn_parametro_operacional_numero('antecedencia_alerta_viatura_inspecao', 15)::integer;
  v_documentos_empresa integer[] := public.fn_parametro_operacional_dias('antecedencias_alerta_documento_empresa', array[15,7,3]);
begin
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select d.empresa_id, 'validade_documento', 'documentos', d.id,
    'Documento a vencer: ' || coalesce(c.nome, d.nome_arquivo, 'colaborador'),
    coalesce(d.tipo_documento, 'Documento') || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade, v_doc_colaborador, d.data_validade - v_doc_colaborador, 'administrativo', 'pendente'
  from public.documentos d
  left join public.colaboradores c on c.id = d.entidade_id
  where d.entidade_tipo = 'colaborador' and d.data_validade is not null
    and d.data_validade - v_doc_colaborador <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count; v_inseridos := v_inseridos + v_parcial;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select d.empresa_id, 'validade_documento', 'documentos', d.id,
    'Documento da empresa a vencer',
    coalesce(d.tipo_documento, d.nome_arquivo, 'Documento') || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade, limiar.dias, d.data_validade - limiar.dias, 'administrativo', 'pendente'
  from public.documentos d
  cross join lateral (
    select min(dias) as dias
    from unnest(v_documentos_empresa) as valores(dias)
    where d.data_validade - current_date <= dias
  ) limiar
  where d.entidade_tipo = 'empresa' and d.data_validade is not null
    and limiar.dias is not null
  on conflict do nothing;
  get diagnostics v_parcial = row_count; v_inseridos := v_inseridos + v_parcial;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select c.empresa_id, 'validade_epi', 'epis', e.id, 'EPI a vencer: ' || c.nome,
    coalesce(to_jsonb(e)->>'tipo_epi', to_jsonb(e)->>'tipo_equipamento', to_jsonb(e)->>'tipo', 'EPI')
      || ' · validade em ' || to_char(e.data_validade, 'DD/MM/YYYY'),
    e.data_validade, v_epi, e.data_validade - v_epi, 'administrativo', 'pendente'
  from public.epis e join public.colaboradores c on c.id = e.colaborador_id
  where c.data_saida is null and e.data_validade is not null
    and e.data_validade - v_epi <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count; v_inseridos := v_inseridos + v_parcial;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select c.empresa_id, 'consulta_medicina', 'medicina_trabalho', m.id,
    'Consulta de medicina a vencer: ' || c.nome,
    'Próxima consulta em ' || to_char(m.data_proxima_consulta, 'DD/MM/YYYY'),
    m.data_proxima_consulta, v_medicina, m.data_proxima_consulta - v_medicina, 'administrativo', 'pendente'
  from public.medicina_trabalho m join public.colaboradores c on c.id = m.colaborador_id
  where c.data_saida is null and m.data_proxima_consulta is not null
    and m.data_proxima_consulta - v_medicina <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count; v_inseridos := v_inseridos + v_parcial;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select v.empresa_id, 'inspecao_viatura', 'viaturas', v.id,
    'Inspeção da viatura a vencer',
    concat_ws(' · ', nullif(v.marca_modelo, ''), nullif(v.matricula, ''),
      'inspeção em ' || to_char(v.data_inspecao_proxima, 'DD/MM/YYYY')),
    v.data_inspecao_proxima, v_inspecao, v.data_inspecao_proxima - v_inspecao, 'administrativo', 'pendente'
  from public.viaturas v
  where v.data_inspecao_proxima is not null
    and v.data_inspecao_proxima - v_inspecao <= current_date
  on conflict do nothing;
  get diagnostics v_parcial = row_count; v_inseridos := v_inseridos + v_parcial;

  return v_inseridos;
end;
$$;

-- Seguro de viatura.
create or replace function public.fn_verificar_alertas_seguro_viaturas()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inseridos integer := 0;
  v_antecedencia integer := public.fn_parametro_operacional_numero('antecedencia_alerta_viatura_seguro', 15)::integer;
begin
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select v.empresa_id, 'seguro_viatura', 'viaturas', v.id,
    'Seguro da viatura a vencer',
    concat_ws(' · ', nullif(v.marca_modelo, ''), nullif(v.matricula, ''),
      'seguro em ' || to_char(v.seguro_data, 'DD/MM/YYYY')),
    v.seguro_data, v_antecedencia, v.seguro_data - v_antecedencia, 'administrativo', 'pendente'
  from public.viaturas v
  where v.seguro_data is not null and v.seguro_data - v_antecedencia <= current_date
  on conflict do nothing;
  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

-- Imóveis e pedidos de orçamento.
create or replace function public.fn_verificar_alertas_imoveis_orcamentos(p_data date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reunioes integer := 0;
  v_orcamentos integer := 0;
  v_condominio integer := public.fn_parametro_operacional_numero('antecedencia_alerta_reuniao_condominio', 7)::integer;
  v_pedidos integer[] := public.fn_parametro_operacional_dias('antecedencias_alerta_pedido_orcamento', array[15,7,3]);
begin
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select i.empresa_id, 'reuniao_condominio', 'imoveis_reunioes_condominio', r.id,
    'Reunião de condomínio · ' || i.nome,
    'Reunião marcada para ' || to_char(r.data, 'DD/MM/YYYY')
      || case when r.hora is not null then ' às ' || to_char(r.hora, 'HH24:MI') else '' end
      || case when nullif(btrim(r.local), '') is not null then ' · ' || r.local else '' end,
    r.data, v_condominio, r.data - v_condominio, 'administrativo', 'pendente'
  from public.imoveis_reunioes_condominio r
  join public.imoveis_empresa i on i.id = r.imovel_id
  where r.data >= p_data and r.data - v_condominio <= p_data
  on conflict do nothing;
  get diagnostics v_reunioes = row_count;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role, estado
  )
  select p.empresa_id, 'prazo_pedido_orcamento', 'pedidos_orcamento', p.id,
    'Prazo de orçamento · ' || p.cliente_nome,
    'Entrega prevista para ' || to_char(p.data_limite_entrega, 'DD/MM/YYYY') || ' · ' || p.descricao_trabalho,
    p.data_limite_entrega, limiar.dias, p.data_limite_entrega - limiar.dias, 'administrativo', 'pendente'
  from public.pedidos_orcamento p
  cross join unnest(v_pedidos) as limiar(dias)
  where p.estado = 'em_curso' and p.data_limite_entrega is not null
    and p.data_limite_entrega >= p_data
    and p.data_limite_entrega - limiar.dias <= p_data
  on conflict do nothing;
  get diagnostics v_orcamentos = row_count;
  return jsonb_build_object('reunioes_condominio_criadas', v_reunioes, 'prazos_orcamento_criados', v_orcamentos);
end;
$$;

revoke all on function public.fn_verificar_alertas_fim_contrato() from public, anon, authenticated;
revoke all on function public.fn_verificar_alertas_vencimento() from public, anon, authenticated;
revoke all on function public.fn_verificar_alertas_seguro_viaturas() from public, anon, authenticated;
revoke all on function public.fn_verificar_alertas_imoveis_orcamentos(date) from public, anon, authenticated;

commit;

-- Auditoria: deve devolver 10 linhas e limite_contrato = 5000.
select chave, descricao, valor, atualizado_por, atualizado_em
from public.parametros_operacionais
order by chave;

select public.fn_limite_contrato_subempreitada() as limite_contrato;

-- Teste reversível: o resultado deve ser 6000 e o rollback repõe o valor anterior.
begin;
update public.parametros_operacionais set valor = '6000'
where chave = 'valor_minimo_contrato_subempreitada';
select public.fn_limite_contrato_subempreitada() as deve_ser_6000;
rollback;
