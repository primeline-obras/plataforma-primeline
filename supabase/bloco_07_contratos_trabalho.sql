-- PRIMELINE | Bloco 7 - alertas escalonados de contratos de trabalho.
-- Executar no SQL Editor do Supabase com uma conta owner.

begin;

-- A verificação passa a ser exclusivamente diária.
drop trigger if exists trg_alerta_fim_contrato
  on public.colaboradores_contratos;

create or replace function public.fn_verificar_alertas_fim_contrato()
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
  v_limiar integer;
begin
  for r in
    select
      cc.id,
      cc.colaborador_id,
      cc.data_fim_prevista,
      c.nome,
      c.empresa_id
    from public.colaboradores_contratos cc
    join public.colaboradores c
      on c.id = cc.colaborador_id
     and c.data_saida is null
    where cc.tipo_contrato = 'a_prazo'
      and cc.estado = 'ativo'
      and cc.data_fim_prevista is not null
  loop
    foreach v_limiar in array array[60, 45, 30]
    loop
      if r.data_fim_prevista - v_limiar = current_date then
        insert into public.alertas (
          empresa_id,
          tipo,
          entidade_tipo,
          entidade_id,
          titulo,
          descricao,
          data_evento_referencia,
          antecedencia_dias,
          data_gatilho,
          destinatario_role,
          estado
        )
        values (
          r.empresa_id,
          'fim_contrato_rh',
          'colaboradores_contratos',
          r.id,
          'Contrato a prazo a terminar: ' || r.nome,
          'Fim previsto em '
            || to_char(r.data_fim_prevista, 'DD/MM/YYYY')
            || ' (' || v_limiar || ' dias de antecedência)',
          r.data_fim_prevista,
          v_limiar,
          current_date,
          'administrativo',
          'pendente'
        )
        on conflict do nothing;
      end if;
    end loop;
  end loop;
end;
$function$;

revoke all
on function public.fn_verificar_alertas_fim_contrato()
from public, anon, authenticated;

-- Mantém o job diário existente e preserva as verificações dos blocos anteriores.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_baselines jsonb := null;
  v_primeiras_consultas integer := 0;
  v_vencimentos integer := 0;
  v_seguros integer := 0;
begin
  if to_regprocedure(
    'public.fn_verificar_congelamentos_pendentes()'
  ) is not null then
    execute
      'select to_jsonb(public.fn_verificar_congelamentos_pendentes())'
    into v_baselines;
  end if;

  if to_regprocedure(
    'public.fn_verificar_primeiras_consultas_medicina()'
  ) is not null then
    v_primeiras_consultas :=
      public.fn_verificar_primeiras_consultas_medicina();
  end if;

  if to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    v_vencimentos :=
      public.fn_verificar_alertas_vencimento();
  end if;

  if to_regprocedure(
    'public.fn_verificar_alertas_seguro_viaturas()'
  ) is not null then
    v_seguros :=
      public.fn_verificar_alertas_seguro_viaturas();
  end if;

  perform public.fn_verificar_alertas_fim_contrato();

  return jsonb_build_object(
    'baselines', v_baselines,
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos,
    'alertas_seguro_criados', v_seguros,
    'contratos_trabalho_verificados', true
  );
end;
$function$;

revoke all
on function public.fn_executar_rotinas_diarias()
from public, anon, authenticated;

-- Garante que um contrato cujo limiar seja hoje não espera pelo dia seguinte.
select public.fn_verificar_alertas_fim_contrato();

commit;

-- Deve devolver as duas funções ativas, o trigger antigo removido e os dois
-- tipos de contrato atualmente usados, sem alterar a respetiva constraint.
select
  to_regprocedure(
    'public.fn_verificar_alertas_fim_contrato()'
  ) is not null as funcao_contratos,
  to_regprocedure(
    'public.fn_executar_rotinas_diarias()'
  ) is not null as rotina_diaria,
  not exists (
    select 1
    from pg_trigger
    where tgname = 'trg_alerta_fim_contrato'
      and not tgisinternal
  ) as trigger_antigo_removido,
  coalesce(
    (
      select jsonb_agg(distinct cc.tipo_contrato order by cc.tipo_contrato)
      from public.colaboradores_contratos cc
      where cc.tipo_contrato is not null
    ),
    '[]'::jsonb
  ) as tipos_em_uso;
