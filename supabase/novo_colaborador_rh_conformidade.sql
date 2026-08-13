-- Primeline | Dados RH, conformidade, EPI e Medicina na admissão
begin;

alter table public.colaboradores
  add column if not exists codigo_rh text,
  add column if not exists seguranca_social boolean not null default false,
  add column if not exists registo_trabalhador boolean not null default false,
  add column if not exists seguro boolean not null default false;

create or replace function public.fn_criar_colaborador_com_alocacao(
  p_nome text,
  p_funcao text,
  p_data_admissao date,
  p_data_nascimento date,
  p_alocacao_tipo text,
  p_obra_id uuid,
  p_nivel text,
  p_valor_hora numeric,
  p_nif text,
  p_email text,
  p_contacto text,
  p_morada text,
  p_codigo_rh text,
  p_seguranca_social boolean,
  p_registo_trabalhador boolean,
  p_seguro boolean,
  p_epi_data date,
  p_medicina_data date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resultado jsonb;
  v_colaborador_id uuid;
  v_colaborador jsonb;
begin
  -- Reutiliza a criação atómica já existente para não duplicar as regras da
  -- empresa, obra ativa e alocação inicial.
  v_resultado := public.fn_criar_colaborador_com_alocacao(
    p_nome, p_funcao, p_data_admissao, p_data_nascimento,
    p_alocacao_tipo, p_obra_id, p_nivel, p_valor_hora,
    p_nif, p_email, p_contacto, p_morada
  );

  v_colaborador_id := (v_resultado -> 'colaborador' ->> 'id')::uuid;

  update public.colaboradores
  set codigo_rh = nullif(btrim(p_codigo_rh), ''),
      seguranca_social = coalesce(p_seguranca_social, false),
      registo_trabalhador = coalesce(p_registo_trabalhador, false),
      seguro = coalesce(p_seguro, false)
  where id = v_colaborador_id
  returning to_jsonb(colaboradores) into v_colaborador;

  if p_epi_data is not null then
    insert into public.epis (
      colaborador_id, tipo_epi, data_entrega, data_validade
    ) values (
      v_colaborador_id, 'Entrega inicial', p_epi_data, null
    );
  end if;

  if p_medicina_data is not null then
    insert into public.medicina_trabalho (
      colaborador_id, data_ultima_consulta, resultado, data_proxima_consulta
    ) values (
      v_colaborador_id, p_medicina_data,
      'Consulta inicial registada na admissão', null
    );
  end if;

  return jsonb_build_object(
    'colaborador', v_colaborador,
    'alocacao', v_resultado -> 'alocacao',
    'epi_criado', p_epi_data is not null,
    'medicina_criada', p_medicina_data is not null
  );
end;
$$;

revoke all on function public.fn_criar_colaborador_com_alocacao(
  text,text,date,date,text,uuid,text,numeric,text,text,text,text,
  text,boolean,boolean,boolean,date,date
) from public;

grant execute on function public.fn_criar_colaborador_com_alocacao(
  text,text,date,date,text,uuid,text,numeric,text,text,text,text,
  text,boolean,boolean,boolean,date,date
) to authenticated;

commit;

select
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'colaboradores'
      and column_name = 'codigo_rh'
  ) as codigo_rh,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'colaboradores'
      and column_name = 'seguranca_social'
  ) as numero_ss,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'colaboradores'
      and column_name = 'registo_trabalhador'
  ) as registo_trabalhador,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'colaboradores'
      and column_name = 'seguro'
  ) as seguro,
  to_regprocedure(
    'public.fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text,text,boolean,boolean,boolean,date,date)'
  ) is not null as criacao_completa;
